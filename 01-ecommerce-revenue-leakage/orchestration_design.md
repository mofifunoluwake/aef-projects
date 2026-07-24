# Orchestration DAG Design — Lumen & Loom Revenue Pipeline

**Tool:** Dagster (recommended) or Airflow
**Schedule:** Daily at 05:00 UTC
**Re-run strategy:** Full refresh (idempotent — safe to re-run any time)

---

## DAG overview

```
source_freshness_check
        │
        ▼
   ┌─ stg_orders
   ├─ stg_payments
   ├─ stg_refunds
   └─ stg_shipping
        │
        ▼
   int_orders_enriched
        │
     ┌──┴───┐
     ▼      ▼
 mart_    mart_monthly
 revenue  _revenue
     │      │
     ▼      ▼
   dbt_test (all 25 tests)
        │
        ▼
   notify_on_completion
```

---

## Schedule and rationale

| Parameter | Value | Rationale |
|---|---|---|
| Schedule | Daily, 05:00 UTC | Runs after overnight source exports (orders, payments, refunds, shipping feeds) land. |
| Run type | Full refresh | Staging are views (free to rebuild); marts are small (10k orders, 12 monthly rows). Incremental logic adds complexity without payoff at this volume. |
| Timeout | 30 minutes | Full build runs in ~20 seconds. 30-min timeout catches warehouse suspension without false alarms. |
| Retry policy | 2 retries, 5-min backoff | Handles transient Snowflake connection drops. |

---

## Source freshness checks

Run `dbt source freshness` as the first step, before any model build.

| Source | loaded_at_field | Warn after | Error after | Action on error |
|---|---|---|---|---|
| raw_orders | updated_at | 36 hours | 48 hours | Block pipeline, alert on-call |
| raw_payments | attempted_at | 36 hours | 48 hours | Block pipeline, alert on-call |
| raw_refunds | requested_at | 5 days | 10 days | Warn only — refunds arrive irregularly |
| raw_shipping | shipped_at | 48 hours | 72 hours | Warn only — carrier feeds are laggy by nature |

**Why orders and payments gate the pipeline:** these are the revenue-critical feeds. Stale
data here means the marts silently under-report revenue — worse than not updating. Refunds
and shipping are naturally laggy, so their thresholds are looser and non-blocking.

---

## Dependency structure

**Layer 1 — Freshness:** `dbt source freshness`. Orders/payments errors block; refunds/shipping warn.

**Layer 2 — Staging (parallel):** stg_orders, stg_payments, stg_refunds, stg_shipping. Views, near-zero runtime.

**Layer 3 — Intermediate:** int_orders_enriched. Depends on all 4 staging models.

**Layer 4 — Marts (parallel):** mart_revenue and mart_monthly_revenue. Both depend on int_orders_enriched. Materialized as tables (full refresh).

**Layer 5 — Testing:** all 25 tests. Business-rule failures at `error` severity block; generic failures at `warn` log but continue.

**Layer 6 — Notification:** success → Slack #data-eng with row counts + duration; failure → PagerDuty + Slack with error detail.

---

## Failure modes and responses

| Failure | Detection | Impact | Response |
|---|---|---|---|
| Snowflake unreachable | Timeout at freshness | No update | Retry 2x, then alert |
| Orders/payments stale | Freshness error | Marts under-report revenue | Block, alert. Never build on stale revenue data. |
| Refunds/shipping stale | Freshness warn | Minor lag | Continue, log warning |
| Staging view fails | dbt build error | Downstream skips | Alert — likely a source schema change |
| Mart build fails | dbt build error | Stale mart served | Alert; last good table remains in place |
| Business-rule test fails | dbt test error | Quality issue in mart | Block, alert, investigate before serving |
| Cash-to-ledger reconciliation breaks | Business-rule test | Net revenue ≠ deduped ledger | CRITICAL — block. This is the engagement's core guarantee. |

---

## Idempotency guarantees

- **Views** (staging): always reflect current source — inherently idempotent.
- **Tables** (marts): `CREATE OR REPLACE` each run — no partial state.
- **No incremental logic** at this data volume.
- **Deterministic:** same raw data + same code = same marts, regardless of run count or timing.
- **Re-run safe:** can be re-run after a failure or manually with no side effects.

---

## Recommended monitoring (not built)

- Last successful run timestamp
- Row counts per mart (detect unexpected drops)
- Test pass/fail trend
- Source freshness status
- Bookings-to-net gap % trend — a sudden shift may signal a source problem, not a real business change

---

## Why Dagster over Airflow

Dagster's asset model maps 1:1 to dbt's ref() graph via `dagster-dbt`, so the orchestrator's
DAG mirrors the dbt lineage automatically. Airflow works too but requires manually wiring
tasks and building custom freshness sensors. Either is acceptable; Dagster reduces the
translation layer between how dbt thinks and how the scheduler thinks.