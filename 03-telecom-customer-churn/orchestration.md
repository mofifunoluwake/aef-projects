# Orchestration DAG Design — Northwind Cellular Churn Pipeline

**Tool:** Dagster (recommended) or Airflow
**Schedule:** Daily at 04:00 UTC
**Re-run strategy:** Full refresh (idempotent)

---

## DAG overview

```
source_freshness_check
        │
        ▼
   ┌─ stg_subscribers
   ├─ stg_plans
   ├─ stg_usage
   ├─ stg_payments
   └─ stg_support_tickets
        │
        ▼
   int_subscriber_signals
        │
        ▼
   mart_subscriber_churn
        │
        ▼
   mart_churn_summary
        │
        ▼
   dbt_test (all 26 tests)
        │
        ▼
   notify_on_completion
```

---

## Schedule and rationale

| Parameter | Value | Rationale |
|---|---|---|
| Schedule | Daily, 04:00 UTC | Runs after overnight mediation + billing batch loads land. Churn flags are re-evaluated each morning against the rolling window. |
| Run type | Full refresh | Staging are views; marts are small (10k subscriber rows, 1 summary row). Usage is 200k+ rows but the dedup + 30-day aggregation is cheap. |
| Timeout | 30 minutes | Full build runs in ~17 seconds. Generous margin for the large usage scan. |
| Retry policy | 2 retries, 5-min backoff | Transient Snowflake drops. |

---

## Observation date handling

The churn definitions are evaluated as-of a fixed observation date (2024-12-31 in the
sandbox). In production this becomes a variable — the pipeline should pass
`observation_date = current_date` (or the previous business day) as a dbt var, so the
30-day no-usage window and the payment-lapse lookback roll forward each run. This keeps the
churn snapshot current without changing model logic.

---

## Source freshness checks

Run `dbt source freshness` first.

| Source | loaded_at_field | Warn after | Error after | Action on error |
|---|---|---|---|---|
| raw_usage | usage_date | 36 hours | 48 hours | Block — stale usage breaks the no-usage signal |
| raw_payments | due_at | 36 hours | 48 hours | Block — stale payments break the lapse signal |
| raw_subscribers | activated_at | 48 hours | 72 hours | Warn — slow-changing dimension |
| raw_support_tickets | opened_at | 5 days | 10 days | Warn — non-critical to churn calc |
| raw_plans | — | n/a | n/a | No check — static reference table |

**Why usage and payments gate the pipeline:** they drive two of the three churn signals.
Stale usage would falsely flag active subscribers as churned (no recent records); stale
payments would miss real lapses. Subscribers and tickets change slowly and are non-blocking.

---

## Dependency structure

**Layer 1 — Freshness:** usage/payments errors block; subscribers/tickets warn.

**Layer 2 — Staging (parallel):** all 5 staging views. Near-zero runtime.

**Layer 3 — Intermediate:** int_subscriber_signals — rolls up usage, payments, tickets per subscriber. This is the heaviest step (scans 200k usage rows).

**Layer 4 — Marts (sequential):** mart_subscriber_churn (per-subscriber flags) → mart_churn_summary (aggregate reconciliation).

**Layer 5 — Testing:** all 26 tests. Business-rule failures at error severity block.

**Layer 6 — Notification:** success → Slack #retention-analytics with the three churn counts + spread; failure → PagerDuty + Slack.

---

## Failure modes and responses

| Failure | Detection | Impact | Response |
|---|---|---|---|
| Snowflake unreachable | Timeout at freshness | No update | Retry 2x, then alert |
| Usage stale | Freshness error | Active subs falsely flagged churned | Block, alert |
| Payments stale | Freshness error | Lapse signal misses real churn | Block, alert |
| Staging view fails | dbt build error | Downstream skips | Alert — likely source schema change |
| Mart build fails | dbt build error | Stale churn snapshot served | Alert; last good table remains |
| Business-rule test fails | dbt test error | Logic error in flags | Block, alert, investigate |
| churned_any < churned_all_three | Business-rule test | Set-logic broken | CRITICAL — the reconciliation math is wrong |

---

## Idempotency guarantees

- **Views** (staging): always reflect current source.
- **Tables** (marts): CREATE OR REPLACE each run.
- **Deterministic:** same raw data + same observation date = same churn flags.
- **Re-run safe:** re-running produces identical output.

---

## Recommended monitoring

- Three churn rates tracked over time (explicit / payment / no-usage) — divergence trend
- The all-three overlap count (should stay small and stable)
- Reactivation count (569 today) — a spike signals a provisioning-sync regression
- Usage freshness — the single most important input to the no-usage signal

---

## Why Dagster over Airflow

Dagster's asset model maps 1:1 to dbt's ref() graph via dagster-dbt, and its native
support for partitioned/parameterized runs makes the rolling observation-date pattern clean
to implement. Airflow works but requires manual sensor wiring for freshness and a custom
mechanism to pass the observation date.
