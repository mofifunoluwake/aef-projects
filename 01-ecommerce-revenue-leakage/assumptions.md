# Assumptions Log — E-Commerce Revenue Leakage

**Client:** Lumen & Loom
**Consultant:** Joy Rereloluwa Ogunmodede
**Date:** July 2026
**Dataset:** 10,000 orders, seed 42, 2024. Reporting currency: USD.

This document records every definitional decision made during the engagement, the
options considered, the decision taken, and the justification. The goal is not to pick
a single "right" answer but to make each choice explicit so Finance and Operations can
each see their own number and understand the others'.

---

## Decision 1: What is a "completed" order?

**Options considered:**
- Placed (order exists)
- Paid (successful payment)
- Shipped (fulfilment started)
- Delivered (carrier confirmed)
- Not-refunded

**Decision:** An order is revenue-recognized when it has a successful payment AND is not
fully refunded. The `ORDER_STATUS = 'completed'` label alone is not sufficient.

**Justification:** Order status is unreliable in this data — 43 cancelled orders were
shipped and 211 placed orders were shipped, meaning the status field drifts from reality.
Payment is the most trustworthy signal that a real, collectible transaction occurred.
Shipping is too unreliable to gate revenue on (637 null ship dates).

---

## Decision 2: When is revenue recognized?

**Options considered:**
- At payment (`processed_at`)
- At ship (`shipped_at`)
- Pro-rated across the fulfilment lifecycle

**Decision:** Revenue is recognized at successful payment.

**Justification:** Ship and delivery dates are unreliable — 637 shipments have null
`SHIPPED_AT` and 456 have null `DELIVERED_AT` due to carrier API timeouts. Recognizing at
payment gives a clean, consistently-populated recognition event. This is also closer to
Finance's cash-oriented view while remaining defensible to Operations.

---

## Decision 3: How are refunds treated?

**Options considered:**
- Net against the original order's month
- Recognize in the month the refund was processed
- Ignore partial refunds / treat all as full

**Decision:** Refunds reduce net revenue. For order-level economics, the refund nets
against the order. A separate refund-by-month view (`refund_month` in stg_refunds)
supports cash-basis reporting in the refund's processed month. Partial refunds (334 of
979) net by their actual `refund_amount`, never the full order value.

**Justification:** 468 refunds (48%) are processed in a later month than the order.
Netting against the order month keeps each order's economics complete and auditable;
the refund-month view lets Finance reconcile cash movement period by period. Handling
partials by actual amount avoids over-crediting.

---

## Decision 4: How are paid-but-cancelled orders handled?

**Options considered:**
- Count as revenue (cash was collected)
- Treat as a liability
- Treat as leakage

**Decision:** Classified as `paid_but_cancelled` — a distinct leakage line, excluded from
clean recognized revenue.

**Justification:** This is money collected on an order that was subsequently cancelled —
a pending refund or liability, not earned revenue. The brief calls this out explicitly as
a leakage question. Making it a named line in the bridge lets Finance quantify exactly how
much cash is sitting against cancelled orders.

---

## Decision 5: Duplicate / retried payments?

**Options considered:**
- Sum all succeeded payments (naive)
- Keep first, drop rest
- Keep first, flag rest

**Decision:** 121 orders have 2 succeeded payments each. Keep the first (by `processed_at`),
flag the others with `is_duplicate_charge`. Only `is_primary_record = true` counts toward
cash and revenue. Duplicate rows are retained for audit, not deleted.

**Justification:** Double-charges are webhook/retry artifacts — the same order genuinely
charged twice by the gateway. Counting both overstates cash by ~$7,000+. Flagging rather
than deleting preserves the evidence trail so the issue can be fixed at source.

---

## Data quality issues found during profiling

| Issue | Count | Severity | Resolution | Source fix needed? |
|---|---|---|---|---|
| Double-charged orders (2 succeeded payments) | 121 | High | Deduped in staging, flagged | Yes — webhook dedup at gateway |
| Refunds crossing month boundary | 468 | Medium | Definitional — refund-month view | Business decision |
| Null shipping timestamps | 637 ship / 456 deliver | Medium | Don't recognize revenue at ship | Yes — carrier API retry/backfill |
| Cancelled/placed orders shipped | 43 + 211 | Medium | Flagged | Yes — order-status sync before fulfilment |
| UPDATED_AT before CREATED_AT | 20 | Low | Flagged (has_invalid_timestamp) | Yes — source timestamp validation |
| Orders with no successful payment | 1,081 | Medium (expected) | Excluded from cash revenue | No — mostly cancelled/open |

---

## Fixed reporting parameters

| Parameter | Value | Rationale |
|---|---|---|
| Reporting currency | USD | Single-currency bridge readability |
| GBP to USD | 1.27 (fixed) | Sprint scope — avoids daily FX dependency |
| EUR to USD | 1.08 (fixed) | Sprint scope |
| Revenue recognition event | Successful payment | Ship dates unreliable (637 nulls) |
| Refund netting | Actual refund_amount | Correct handling of 334 partial refunds |
| Duplicate policy | Keep first succeeded, flag rest | Avoids overcounting cash |