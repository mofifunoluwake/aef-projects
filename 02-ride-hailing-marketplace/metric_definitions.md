# Business Metric Definitions — Ride-Hailing Marketplace

Each metric has one definition. Where teams disagree (active rider), all competing
definitions are computed and exposed; the recommended default is noted. All monetary
values are in USD (GBP × 1.27 fixed rate).

| Metric | Definition | Model / Column | Notes |
|---|---|---|---|
| **GMV** | Sum of gross_fare_usd for all trips with gross_fare > 0 | mart_marketplace_kpis.gmv_usd | Includes completed + billed cancellations. Excludes zero-fare cancellations. Growth's headline. |
| **Net revenue** | Captured cash (deduped) minus processor fees | mart_marketplace_kpis.net_revenue_usd | Only money actually collected and retained. Fraud fares reversed. |
| **Take rate** | Net revenue / GMV × 100 | mart_marketplace_kpis.take_rate_pct | Marketplace efficiency metric. |
| **Active rider (recommended)** | Completed ≥1 non-fraud trip in trailing 30 days from latest data date | mart_rider_activity.is_active_clean_30d | Strictest defensible count. 918 riders. |
| **Active rider (alternatives)** | CRM flag / requested 30d / completed 30d | mart_rider_activity (3 other bool columns) | 3,055 / 1,090 / 947. Exposed for each stakeholder. |
| **Completion rate** | Completed trips / total trips × 100 | mart_driver_performance.completion_rate_pct | Per-driver. Includes fraud completions. |
| **Fraud rate** | Fraud-flagged trips / completed trips × 100 | mart_marketplace_kpis.fraud_rate_pct | Denominator is completed only (fraud doesn't apply to cancellations). |
| **Cancellation rate** | Cancelled trips / total trips × 100 | Derived from mart_marketplace_kpis | All cancellation types combined. |
| **Incentive spend** | Sum of all bonus_amount_usd from the payouts ledger | mart_driver_performance.total_incentive_paid_usd | Includes both lines on overlapping campaigns. Reconciles to raw ledger ($17,144.71). |
| **Reporting currency** | USD | all _usd columns | GBP × 1.27 fixed rate. |

## Definitional contract

- **Active rider is a range, not a scalar.** The CRM number (3,055) is nearly 3× the real
  activity (918). Any single-number report must state which definition it uses. Recommended
  default for investor reporting is the strictest (clean completed, 30d).
- **GMV includes billed cancellations but not zero-fare cancellations.** A cancellation fee
  is real cash; a no-driver-found cancellation is not marketplace activity.
- **Fraud fares stay in GMV but reverse out of net revenue** in the period the flag was set.
- **Driver payout totals are sacred** — incentive spend reconciles to the raw payouts
  ledger and is never silently restated, even for fraud trips.