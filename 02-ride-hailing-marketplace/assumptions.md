# Assumptions Log — Ride-Hailing Marketplace Engagement

**Consultant:** Analytics Engineering Fellow
**Client:** Cobalt Mobility
**Date:** July 2026
**Dataset:** 15,000 trips, seed 42, Jan–Dec 2024

This document records every definitional decision made during the engagement,
the options considered, the decision taken, and the justification. Each decision
was made to produce a defensible, reconcilable set of marts — not to pick a
"right" answer, but to make the choice explicit so stakeholders can see their
own number and understand the others.

---

## Decision 1: What counts as an "active rider"?

**Options considered:**
| Definition | Count | Notes |
|---|---|---|
| CRM flag (`account_status = 'active'`) | 3,055 | Just means account not closed. Includes riders who signed up and never rode. |
| Requested any trip in trailing 30 days | 1,090 | Growth's preferred. Includes cancelled and fraud trips. |
| Completed any trip in trailing 30 days | 947 | Ops view. Includes fraud-flagged trips. |
| Completed a non-fraud trip in trailing 30 days | 918 | Finance view. Strictest. |

**Decision:** All four definitions are exposed side by side in `mart_rider_activity`.
The **recommended primary definition** is Definition 4 (clean completed, trailing 30 days)
because it measures riders who actually generated collectible revenue.

**Justification:** The 15.8% swing between Growth's count (1,090) and Finance's count (918)
is the source of the "how many active riders do we have" disagreement. Rather than
picking one and hiding the others, the mart lets each team read their own number from
the same table. The recommended default for investor reporting is the strictest count
because overstating active riders in a Series C is a due-diligence risk.

**Trailing window anchored to:** latest trip date in the dataset (not `current_timestamp()`),
so the definition remains valid regardless of when the pipeline runs relative to data
freshness.

---

## Decision 2: How are cancelled trips classified?

**Options considered:**
- Include all cancellations in GMV (Growth's position)
- Exclude all cancellations from GMV (Finance's position)
- Split by whether a fare was charged

**Decision:** Split into two categories:
- **Billed cancellations** (1,056 trips, fare > 0): classified as `billed_cancellation`.
  The cancellation fee is real revenue collected from the rider. Reported as a separate
  "cancellation fee revenue" line in the bridge, not lumped into core trip GMV.
- **Zero-fare cancellations** (1,394 trips, fare = 0): classified as `zero_fare_cancellation`.
  No money changed hands. Excluded from GMV and revenue entirely.

**Sub-decision on `no_driver_found`:** All 602 `no_driver_found` cancellations are zero-fare.
These represent a platform failure (no supply), not marketplace activity. They are counted
in trip volume metrics but excluded from all revenue metrics.

**Justification:** Counting a zero-fare cancellation in GMV inflates the marketplace's
apparent size with trips where no value was created. Conversely, a billed cancellation
represents real cash collected — ignoring it understates revenue. The split makes both
sides visible.

---

## Decision 3: How does fraud flow through revenue?

**Profiling evidence:**
- 395 fraud-flagged trips (3.15% of completed trips)
- All fraud flags are on completed trips (zero on cancelled)
- 169 incentive lines ($494.19 USD-equivalent) were paid on fraud-flagged trips

**Decision:**
- Fraud-flagged trip fares **remain in GMV** (the trip happened on the platform — Growth
  is correct that it's marketplace activity) but are **reversed out of net revenue**
  as a "fraud reversal" line in the reconciliation bridge.
- The reversal is recorded in the **period the flag was set**, not the trip period.
  This matches Finance's accrual logic: revenue was recognized at trip completion,
  then reversed when the fraud team flagged it.
- Incentives paid on fraud trips ($494.19) are **surfaced as a separate cost line**
  ("fraud incentive exposure") but are **NOT clawed back from driver payout totals**.
  This respects the Driver Ops constraint: a driver's paid bonus total must reconcile
  to the payouts ledger. We surface the problem; we do not silently restate history.

**Justification:** The Driver Ops Head was explicit: driver-facing payout history cannot
quietly change, or the support queue explodes. The correct action is to surface the
$494.19 as a finding and let Finance decide whether to implement a prospective clawback
policy. The model does not make that policy decision — it makes the exposure visible.

---

## Decision 4: Revenue recognition timing and currency

**Timing decision:** Revenue is recognized at **trip completion** (`ended_at`), not at
payment capture (`captured_at`). Rationale: the service was delivered at trip end;
payment capture is a settlement event that can lag by hours or days due to retries.

**Currency decision:** All monetary amounts are reported in **USD**. GBP amounts
(rivermouth market, ~24% of the marketplace) are converted at a **fixed rate of
1 GBP = 1.27 USD**.

**Why a fixed rate:** This is a 2-week consulting sprint on a single year of data.
Implementing a daily FX rate lookup adds pipeline complexity (external API dependency,
rate-not-found failure mode) with minimal analytical benefit for a dataset that spans
only 12 months. The fixed rate is documented and can be replaced with a daily rate
table in production if the business requires it.

**Where the conversion happens:** `int_trips_enriched`. Every monetary column has
both a local-currency and a `_usd` version. The `fx_rate_to_usd` column makes the
applied rate auditable row by row.

---

## Decision 5: Deduplication strategy

### Duplicate captured payments
**Finding:** 210 trips have 2 successful captured payment rows (different `PAYMENT_ID`,
same `TRIP_ID`, same `AMOUNT`). This is the webhook double-logging the Data Lead suspected.

**Decision:** In `stg_payments`, both rows are kept. A `is_primary_record` flag marks the
first capture (by `captured_at`) as the one to use for revenue sums. The duplicate is
preserved for auditability — it is flagged (`is_duplicate_capture = true`), not silently
dropped.

**Impact if not deduped:** 210 trips would be double-counted in captured revenue,
inflating net revenue.

### Duplicate driver rows (re-onboarding)
**Finding:** 30 drivers have 2 rows in `RAW_DRIVERS` due to `DRIVER_ID` reuse.

**Decision:** In `stg_drivers`, collapsed to 1 row per driver using the latest
`ONBOARDED_AT`. The `is_reonboarded` flag and `onboarding_count` column preserve
visibility. No driver history is lost — the dedup is documented and testable.

### Multi-campaign incentive lines
**Finding:** 1,213 trips have 2 incentive lines each (the trip qualified for 2 campaigns).

**Decision:** Both lines are **kept and summed** — this is not a duplicate, it is genuine
double-qualification. The driver was actually paid both bonuses. When reporting "incentive
cost per trip," the full sum is used. The `is_multi_campaign` flag surfaces which trips
are double-attributed so the business can evaluate whether campaign overlap rules need
tightening. Driver payout totals include both lines (to reconcile with the payouts ledger).

---

## Data quality issues found during profiling

| Issue | Severity | Resolution | Source fix needed? |
|---|---|---|---|
| 30 drivers with duplicate `DRIVER_ID` (re-onboarding) | Medium | Deduped in staging, flagged | Yes — onboarding system should assign new IDs |
| 210 duplicate captured payments (webhook) | High | Flagged in staging, `is_primary_record` for revenue | Yes — webhook dedup at ingestion |
| 1,213 trips with overlapping incentive campaigns | Low | Kept as-is (genuine), flagged | Business decision — tighten campaign overlap rules? |
| 169 incentive lines on fraud-flagged trips ($494) | Medium | Surfaced, not clawed back | Yes — add fraud check before incentive payout |
| Timestamp corruption on Snowflake load (Python 3.14) | High | Fixed via string-formatted reload | Yes — pin connector version or add timestamp validation |
| 1,775 trips with no payment row | Medium | Documented — 1,394 are zero-fare (expected), ~381 unexplained | Yes — investigate billing gaps |
| `ACCOUNT_STATUS` misleading as activity signal | Low | Documented, separate definitions built | No — just don't use it as an activity metric |

---

## Fixed reporting parameters

| Parameter | Value | Rationale |
|---|---|---|
| Reporting currency | USD | Single-currency bridge readability |
| GBP→USD rate | 1.27 (fixed) | Avoids external FX dependency for sprint scope |
| Active-rider trailing window | 30 days | Industry standard for ride-hailing MAU |
| Window anchor | Latest trip date in dataset | Ensures definition works regardless of pipeline run date |
| Revenue recognition event | Trip completion (`ended_at`) | Service delivery, not settlement |