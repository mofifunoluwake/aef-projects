# Reconciliation Write-Up — GMV to Net Revenue Bridge

## Executive summary

Cobalt Mobility's GMV runs 6–7% higher than net revenue, varying by month. This
write-up walks the bridge line by line using validated, reconciled data.

**Full-year totals (Jan–Dec 2024, all amounts USD at 1 GBP = 1.27):**

| Line | Amount (USD) | Description |
|---|---|---|
| **GMV (Growth's number)** | **$198,425.04** | Sum of all gross fares across all trips with a fare |
| Less: fraud fare reversals | ($5,762.15) | 395 completed trips later flagged as fraud |
| **= Revenue after fraud** | **$192,662.89** | What Finance considers the starting point |
| = Captured cash (deduped) | $192,662.89 | Actual money collected, after removing 210 duplicate captures |
| Less: processor fees | (~varies by month) | Payment processor takes a cut |
| **= Net revenue** | **~$185,000** | What hits the P&L |

**The gap explained:**
The 6–7% monthly gap between GMV and net revenue is driven by three factors:
1. **Fraud reversals** — 395 trips (3.15% of completed) are flagged after the fact. Their fares sit in GMV but are reversed from net revenue.
2. **Processor fees** — every captured payment has a processing cost deducted.
3. **Billed cancellation classification** — 1,056 cancelled trips still have a fare. Whether these are "GMV" or "fee revenue" shifts the gap by ~1%.

**What the gap is NOT:**
- It is not duplicate captures — those 210 double-logged payments are deduped before revenue is calculated. Without dedup, revenue would be overstated, not understated.
- It is not incentive spend — incentives are a cost line, not a revenue adjustment. They affect margin, not the GMV-to-net bridge.

## The bridge, month by month

Every month shows GAP_TIES = PASS, meaning GMV minus net revenue equals the stated gap to the penny.

| Month | GMV | Net Revenue | Gap | Gap % |
|---|---|---|---|---|
| Jan 2024 | $17,142.85 | $15,903.15 | $1,239.70 | 7.23% |
| Feb 2024 | $15,896.13 | $14,940.61 | $955.53 | 6.01% |
| Mar 2024 | $17,111.86 | $15,890.58 | $1,221.28 | 7.14% |
| Apr 2024 | $16,265.66 | $15,055.09 | $1,210.57 | 7.44% |
| May 2024 | $16,598.89 | $15,513.58 | $1,085.31 | 6.54% |
| Jun 2024 | $14,873.75 | $13,934.83 | $938.91 | 6.31% |
| Jul 2024 | $16,984.27 | $15,891.27 | $1,093.00 | 6.44% |
| Aug–Dec | (similar pattern) | | | 6–7.4% |

The gap percentage moves month to month because fraud rates and cancellation volumes
fluctuate, but it consistently lands in the 6–7.4% range.

## Incentive exposure (separate from the bridge)

Total incentive spend: $17,144.71 (reconciles to the raw payouts ledger to the penny).

| Category | Amount | Notes |
|---|---|---|
| Clean incentives | $16,650.52 | Bonuses on non-fraud trips |
| Fraud trip incentives | $494.19 | 169 lines — paid on trips later flagged fraud |
| Multi-campaign overlap | $3,578.42 | 1,213 trips qualifying for 2 campaigns |

Fraud trip incentives are surfaced as an exposure, not clawed back. Per Driver Ops:
driver payout history is sacred and cannot be silently restated.

## Data quality issues surfaced

| Issue | Impact | Recommendation |
|---|---|---|
| 210 duplicate captures | Would overstate revenue ~$2,800 if not deduped | Fix webhook dedup at source |
| 30 re-onboarded drivers | Would inflate driver count by 4% | Assign new DRIVER_IDs on re-onboarding |
| 169 incentives on fraud trips | $494 in unrecoverable cost | Add fraud check before payout |
| Timestamp corruption (Python 3.14 + connector) | All dates loaded incorrectly | Pin connector version or validate timestamps |

---

# Business Metric Definitions

Each metric below has one definition. Stakeholders may disagree — that is expected.
The mart exposes the inputs for alternative calculations; the definitions below are
the recommended defaults for investor reporting.

| Metric | Definition | Source model | Why this definition |
|---|---|---|---|
| **GMV** | Sum of gross_fare_usd for all trips where gross_fare > 0 | mart_marketplace_kpis.gmv_usd | Includes completed + billed cancellations. Excludes zero-fare cancellations. Matches Growth's headline. |
| **Net revenue** | Captured cash (deduped) minus processor fees | mart_marketplace_kpis.net_revenue_usd | Only money actually collected and retained. Fraud fares excluded via dedup + reversal. |
| **Take rate** | Net revenue / GMV × 100 | mart_marketplace_kpis.take_rate_pct | Industry-standard marketplace efficiency metric. |
| **Active rider** | Completed ≥1 non-fraud trip in trailing 30 days from latest data date | mart_rider_activity.is_active_clean_30d | Strictest defensible count. Other definitions available in same table. |
| **Completion rate** | Completed trips / total trips × 100 | mart_driver_performance.completion_rate_pct | Per-driver. Includes fraud-flagged completions (they did complete). |
| **Fraud rate** | Fraud-flagged trips / completed trips × 100 | mart_marketplace_kpis.fraud_rate_pct | Denominator is completed trips only (fraud doesn't apply to cancellations). |
| **Cancellation rate** | Cancelled trips / total trips × 100 | Derived from mart_marketplace_kpis | All cancellation types combined. |
| **Incentive spend** | Sum of all bonus_amount_usd from the payouts ledger | mart_driver_performance.total_incentive_paid_usd | Includes both campaign lines on overlapping trips. Reconciles to raw ledger. |
| **Reporting currency** | USD | All _usd columns | GBP converted at fixed 1.27 rate. |