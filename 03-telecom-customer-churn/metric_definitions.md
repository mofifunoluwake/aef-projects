# Business Metric Definitions — Telecom Customer Churn

Each metric has one definition. Where teams disagree (churn), all competing definitions
are computed and exposed; the recommended headline is noted.

| Metric | Definition | Model / Column | Notes |
|---|---|---|---|
| **Churn rate (headline)** | Subscribers with account_status = 'cancelled' / total | mart_churn_summary.explicit_rate_pct | 13.81%. Most conservative. Recommended board number. |
| **Payment-lapse rate** | Subscribers with 1+ past-due period / total | mart_churn_summary.payment_lapse_rate_pct | 15.30%. Billing's leading indicator. |
| **No-usage rate** | Subscribers with zero usage in trailing 30d / total | mart_churn_summary.no_usage_rate_pct | 23.57%. Network's earliest signal. |
| **Churned (any)** | Flagged by at least one definition | mart_churn_summary.churned_any | 3,819 (38.2%). Widest possible view. |
| **Churned (all three)** | Flagged by all three definitions | mart_churn_summary.churned_all_three | 253 (2.5%). The hard-core churned. |
| **Reactivation count** | Cancelled but used network in trailing 30d | mart_churn_summary.likely_reactivated | 569. Provisioning/billing sync issue. |
| **Voluntary churn** | Cancelled with disconnect_reason = voluntary | mart_subscriber_churn.churn_type | 816. Satisfaction-driven; retention-addressable. |
| **Involuntary churn** | Cancelled with disconnect_reason = involuntary | mart_subscriber_churn.churn_type | 451. Non-payment; collections problem. |
| **Ported-out churn** | Cancelled with disconnect_reason = ported_out | mart_subscriber_churn.churn_type | 125. Left for a competitor. |
| **Observation date** | Fixed as-of date for all churn evaluation | (dbt var in production) | 2024-12-31 in sandbox. |

## Definitional contract

- **Churn is a range, not a scalar.** Any single-number churn report must state which
  definition it uses. The recommended default is explicit cancellation (13.81%).
- **Leading indicators are not headline churn.** Payment-lapse and no-usage precede formal
  cancellation and are for retention targeting, not board reporting.
- **Involuntary churn is excluded from win-back targeting.** Use churn_type to filter.
