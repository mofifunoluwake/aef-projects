# Reconciliation Write-Up — Bookings to Net Revenue

**Client:** Lumen & Loom

**Date:** July 2026
**Dataset:** 10,000 orders, seed 42, 2024. Reporting currency: USD.

**Consultant:** Joy Rereloluwa Ogunmodede

**The question:** Finance and Operations report revenue numbers that differ by 8–12% each
month. The board wants one source of truth.

---

## Executive summary

The gap between gross bookings and net revenue runs 17.7%–22.9% per month. The narrower
8–12% figure the board hears is the disagreement between two *reporting choices* (Finance's
cash/booking view vs Operations' fulfilled view) — that gap is one slice of this wider
bridge. Both stakeholders' numbers sit inside the bridge below. The mart lets each read
their own figure and see exactly what separates them.

**Cash reconciliation:** Net captured cash = **$615,917.65**, tying exactly to the deduped
raw payment ledger. This is the brief's non-negotiable, and it passes to the penny.

---

## The bridge (bookings → net revenue)

| Line | What it represents |
|---|---|
| **Gross bookings** | Every order's amount, all statuses. Finance's most optimistic figure. |
| Less: cancelled & unpaid | 912 orders cancelled and never paid — bookings noise, no cash. |
| Less: unpaid open orders | placed/confirmed with no successful payment yet. |
| Less: paid-but-cancelled | Cash collected, then order cancelled — leakage / pending liability. |
| Less: duplicate charge exposure | 121 orders double-charged; second charge removed from cash. |
| Less: refunds | ~$54,500 refunded; 48% land in a different month than the order. |
| **= Net revenue** | Deduped captured cash minus refunds. |

---

## Monthly detail

| Month | Gross Bookings | Net Revenue | Gap | Gap % |
|---|---|---|---|---|
| Jan 2024 | $63,229.22 | $50,607.51 | $12,621.71 | 19.96% |
| Feb 2024 | $55,720.67 | $45,551.38 | $10,169.29 | 18.25% |
| Mar 2024 | $57,682.83 | $44,493.67 | $13,189.16 | 22.86% |
| Apr 2024 | $55,458.88 | $44,804.99 | $10,653.89 | 19.21% |
| May 2024 | $60,748.21 | $47,763.19 | $12,985.02 | 21.38% |
| Jun 2024 | $53,682.98 | $42,967.86 | $10,715.12 | 19.96% |
| Jul 2024 | $62,632.33 | $51,525.18 | $11,107.14 | 17.73% |
| Aug–Dec | (same pattern) | | | 17–23% |

The gap percentage moves month to month because cancellation volume, unpaid-order counts,
and refund timing all fluctuate.

---

## What drives the gap (ranked)

1. **Unpaid orders** (cancelled + open) — the largest component. Orders that exist as
   bookings but never converted to cash. This is what Operations means by "wishful thinking."
2. **Refunds** — ~$54,500, with 48% crossing month boundaries. This is the timing mismatch
   Finance and Ops argue about.
3. **Paid-but-cancelled leakage** — cash sitting against cancelled orders.
4. **Duplicate charges** — smallest line, but real: 121 orders would double-count without
   dedup.

---

## Data quality issues surfaced (for the client to fix at source)

| Issue | Count | Recommendation |
|---|---|---|
| Double-charges (webhook/retry) | 121 orders | Gateway-level dedup before persistence |
| Cross-month refunds | 468 | Agree a recognition-month policy |
| Null shipping timestamps | 637 ship / 456 deliver | Carrier API retry + backfill |
| Cancelled/placed orders shipped | 43 + 211 | Sync order status before fulfilment release |
| UPDATED_AT before CREATED_AT | 20 | Source-side timestamp validation |

---

## What I fixed vs what the client must fix

**Fixed in the pipeline:** duplicate-charge dedup, currency normalization (USD via fixed
GBP×1.27 / EUR×1.08), revenue classification, refund netting, invalid-timestamp flagging.

**Client must fix at source:** the webhook double-logging, the carrier timestamp gaps, and
the order-status-vs-fulfilment desync. These are upstream data-generation problems the
warehouse can flag but not cure.