# Orchestration DAG Design — RideFlow Pipeline

**Tool:** Dagster (recommended) or Airflow
**Schedule:** Daily at 06:00 UTC
**Re-run strategy:** Full refresh (idempotent — safe to re-run at any time)

---

## DAG overview

```
source_freshness_check
        │
        ▼
   ┌─ stg_riders
   ├─ stg_drivers
   ├─ stg_trips ────────────────┐
   ├─ stg_payments ─────────────┤
   └─ stg_driver_incentives ────┤
                                ▼
                     int_trips_enriched
                        │
              ┌─────────┼──────────┐
              ▼         ▼          ▼
    mart_driver    mart_rider   mart_marketplace
    _performance   _activity    _kpis
              │         │          │
              ▼         ▼          ▼
         dbt_test (all 50 tests)
              │
              ▼
         notify_on_completion
```

---

## Schedule and rationale

| Parameter | Value | Rationale |
|---|---|---|
| Schedule | Daily, 06:00 UTC | Runs after overnight source-system exports land. Cobalt operates in 4 cities, likely spanning UTC-5 to UTC+1 — 06:00 UTC catches all timezones' previous business day. |
| Run type | Full refresh | All staging models are views (zero compute cost to "rebuild"). Mart tables are small (750 + 3,750 + 12 rows) — full table rebuild is cheaper than incremental merge logic for this data volume. |
| Timeout | 30 minutes | Current full build takes ~15 seconds on XS warehouse. 30-minute timeout catches warehouse suspension or Snowflake outage without false alarms. |
| Retry policy | 2 retries, 5-minute backoff | Handles transient Snowflake connection drops. If all retries fail, alert fires. |

---

## Source freshness checks

Run `dbt source freshness` as the first DAG step, before any model builds.

| Source table | loaded_at_field | Warn after | Error after | Action on error |
|---|---|---|---|---|
| raw_trips | requested_at | 36 hours | 48 hours | Block pipeline, alert on-call |
| raw_payments | attempted_at | 36 hours | 48 hours | Block pipeline, alert on-call |
| raw_driver_incentives | paid_at | 8 days | 14 days | Warn only — weekly batch, so 7+ days is normal |
| raw_riders | signup_at | N/A | N/A | No freshness check — slow-changing dimension |
| raw_drivers | onboarded_at | N/A | N/A | No freshness check — slow-changing dimension |

**Why trips and payments are gating:** These are the transactional feeds. If they're stale,
the marts will silently report incomplete revenue — which is worse than not updating at all.
Incentives are a weekly batch, so staleness up to ~8 days is expected behavior.

---

## Dependency structure

### Layer 1: Source freshness
- `dbt source freshness` — must pass before anything else runs
- If trips or payments error: pipeline stops, alert fires
- If incentives warn: log warning, continue (expected for weekly batch)

### Layer 2: Staging views (parallel)
- `stg_riders`, `stg_drivers`, `stg_trips`, `stg_payments`, `stg_driver_incentives`
- All run in parallel (no cross-dependencies at this layer)
- Materialized as views — essentially zero runtime

### Layer 3: Intermediate (waits for staging)
- `int_trips_enriched` depends on `stg_trips`, `stg_payments`, `stg_driver_incentives`
- Materialized as ephemeral (compiled into downstream queries, not stored)

### Layer 4: Marts (parallel, wait for intermediate + staging)
- `mart_driver_performance` depends on `stg_drivers`, `stg_driver_incentives`, `int_trips_enriched`
- `mart_rider_activity` depends on `stg_riders`, `int_trips_enriched`
- `mart_marketplace_kpis` depends on `int_trips_enriched`
- All three run in parallel
- Materialized as tables (full refresh)

### Layer 5: Testing
- `dbt test` — all 50 tests run after marts complete
- Business-rule test failures at `error` severity block the pipeline
- Generic test failures at `warn` severity log but don't block

### Layer 6: Notification
- On success: Slack message to #data-eng channel with row counts and run duration
- On failure: PagerDuty alert to on-call analytics engineer + Slack message with error details

---

## Failure modes and responses

| Failure | Detection | Impact | Response |
|---|---|---|---|
| Snowflake unreachable | Connection timeout at freshness step | No models update | Auto-retry 2x, then alert on-call |
| Source data stale (trips/payments) | Freshness check error | Marts would show incomplete day | Pipeline blocked, alert on-call. Do NOT build on stale data. |
| Source data stale (incentives) | Freshness check warn | Incentive spend may lag | Pipeline continues. Warning logged. Expected for weekly batch. |
| Staging view creation fails | dbt build error | Downstream models skip | Alert on-call. Usually a schema change in source — check raw table DDL. |
| Mart build fails | dbt build error | Stale mart served to dashboards | Alert on-call. Last successful mart remains in place (table, not view). |
| Test failure (business-rule) | dbt test error severity | Data quality issue in mart | Pipeline blocked. Alert on-call. Investigate before serving data. |
| Test failure (generic) | dbt test warn severity | Minor quality issue | Pipeline continues. Warning logged for next-day review. |
| Driver incentive reconciliation breaks | Business-rule test | Payout totals don't match ledger | CRITICAL — pipeline blocked. This is a non-negotiable from Driver Ops. |

---

## Idempotency guarantees

- **Views** (staging): inherently idempotent — always reflect current source data
- **Ephemeral** (intermediate): compiled inline, no stored state
- **Tables** (marts): `CREATE OR REPLACE TABLE` on every run — full refresh, no partial state
- **No incremental logic**: at this data volume (<100K rows), incremental adds complexity without benefit
- **Deterministic output**: same raw data + same code = same mart contents, regardless of run count or timing
- **Re-run safety**: pipeline can be re-run at any time (after a failure, for testing, manually) with no side effects

---

## Monitoring dashboard (recommended, not built)

For production deployment, recommend a simple monitoring view:
- Last successful run timestamp
- Row counts per mart (detect unexpected drops)
- Test pass/fail trend (detect creeping quality issues)
- Source freshness status (detect upstream delays)
- GMV-to-net gap percentage trend (detect business anomalies — a sudden gap change may indicate a source-system issue, not just business fluctuation)

---

## Why Dagster over Airflow

| Criterion | Dagster | Airflow |
|---|---|---|
| dbt integration | Native `dagster-dbt` — auto-generates assets from dbt manifest | Requires `BashOperator` or third-party provider |
| Asset-based model | DAG mirrors dbt's ref() graph naturally | Task-based — must manually wire dependencies |
| Local dev | `dagster dev` runs locally with full UI | Requires Docker or managed service for local testing |
| Freshness | Built-in asset freshness policies | Must build custom sensors |

Either tool works. Dagster is recommended because its asset model maps 1:1 to dbt's model graph, reducing the translation layer between "how dbt thinks" and "how the orchestrator thinks."