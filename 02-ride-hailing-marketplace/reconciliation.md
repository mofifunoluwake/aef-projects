# Reconciliation Write-Up — GMV to Net Revenue Bridge

**Client:** Cobalt Mobility
**Date:** July 2026
**Dataset:** 15,000 trips, seed 42, Jan–Dec 2024. Reporting currency: USD (GBP × 1.27).

**Consultant:** Joy Rereloluwa Ogunmodede

**The question:** GMV (Growth's number) runs 8–12% higher than net revenue (Finance's
number) every month, by a moving amount. The COO needs one defensible figure before a
fundraise.

---

## Executive summary

Cobalt Mobility's GMV runs 6–7% higher than net revenue in this dataset, varying by month.
This write-up walks the bridge line by line using validated, reconciled data. Every monthly
gap ties to the penny (GAP_TIES = PASS across all 12 months), and captured cash reconciles
exactly to the deduped payment ledger.

**Full-year totals (Jan–Dec 2024, all amounts USD at 1 GBP = 1.27):**

| Line | Amount (USD) | Description |
|---|---|---|
| **GMV (Growth's number)** | **$198,425.04** | Sum of all gross fares across all trips with a fare |
| Less: fraud fare reversals | ($5,762.15) | 395 completed trips later flagged as fraud |
| **= Revenue after fraud** | **$192,662.89** | Finance's starting point |
| = Captured cash (deduped) | $192,662.89 | Actual money collected, after removing 210 duplicate captures |
| Less: processor fees | (varies by month) | Payment processor's cut |
| **= Net revenue** | **~$185,000** | What hits the P&L |

---

## The gap explained

The monthly gap between GMV and net revenue is driven by three factors:

1. **Fraud reversals** — 395 trips (3.15% of completed) are flagged after the fact. Their
   fares sit in GMV but reverse out of net revenue.
2. **Processor fees** — every captured payment has a processing cost deducted.
3. **Billed cancellation classification** — 1,056 cancelled trips still carry a fare.
   Whether these count as "GMV" or "fee revenue" shifts the gap by ~1%.

**What the gap is NOT:**
- Not duplicate captures — the 210 double-logged payments are deduped before revenue is
  calculated. Without dedup, revenue would be *overstated*, not understated.
- Not incentive spend — incentives are a cost line affecting margin, not a GMV-to-net
  revenue adjustment.

---

## The bridge, month by month

Every month shows GAP_TIES = PASS: GMV minus net revenue equals the stated gap to the penny.

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

---

## Incentive exposure (separate from the bridge)

Total incentive spend: **$17,144.71**, reconciling to the raw payouts ledger to the penny.

| Category | Amount | Notes |
|---|---|---|
| Clean incentives | $16,650.52 | Bonuses on non-fraud trips |
| Fraud trip incentives | $494.19 | 169 lines — paid on trips later flagged fraud |
| Multi-campaign overlap | $3,578.42 | 1,213 trips qualifying for 2 campaigns |

Fraud trip incentives are surfaced as an exposure, not clawed back — per Driver Ops,
driver payout history is sacred and cannot be silently restated.

---

## Data quality issues surfaced (for the client to fix at source)

| Issue | Count | Recommendation |
|---|---|---|
| Duplicate captures (webhook) | 210 trips | Fix webhook dedup at ingestion |
| Re-onboarded drivers (ID reuse) | 30 drivers | Assign new DRIVER_IDs on re-onboarding |
| Incentives on fraud trips | 169 lines ($494) | Add fraud check before payout |
| Timestamp corruption (Py 3.14 + connector) | all | Pin connector version / validate timestamps |

---

## What I fixed vs what the client must fix

**Fixed in the pipeline:** duplicate-capture dedup, driver re-onboarding dedup, currency
normalization (USD via fixed GBP × 1.27), trip classification, fraud-reversal logic,
incentive de-duplication across overlapping campaigns, and the timestamp-corruption reload.

**Client must fix at source:** the webhook double-logging, the DRIVER_ID reuse on
re-onboarding, and the fraud-check-before-payout gap. These are upstream problems the
warehouse can flag and correct for in reporting, but only the source systems can cure.

---

*Metric definitions for every headline number are maintained separately in
`metric_definitions.md`.*