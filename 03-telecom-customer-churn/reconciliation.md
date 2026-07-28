# Reconciliation Write-Up — Three Churn Definitions

**Client:** Northwind Cellular
**Consultant:** Joy Rereloluwa Ogunmodede
**Date:** July 2026
**The question:** Marketing, Billing, and Network each report a different churn rate to the CEO. Which one is right?

---

## Executive summary

All three are "right" — they measure different things. Northwind's churn rate is not one
number; it is a range from **13.8% to 23.6%** depending on the definition. The critical
finding is that these definitions barely overlap: only **2.5% of subscribers** are churned
under all three. So the teams are not counting the same people three ways — they are
describing three genuinely different populations. This model computes all three from one
source, so the disagreement can be managed instead of argued.

---

## The three definitions reconciled

| Definition | Owner | Count | Rate | What it captures |
|---|---|---|---|---|
| Explicit cancellation | Marketing | 1,381 | 13.81% | Formally quit — status set to cancelled |
| Payment lapse | Billing | 1,530 | 15.30% | Stopped paying — 1+ past-due period |
| No usage (30 days) | Network | 2,357 | 23.57% | Went silent — zero usage Dec 1–31 |

- **Churned under ANY definition:** 3,819 (38.2%)
- **Churned under ALL THREE:** 253 (2.5%)
- **Likely reactivated (cancelled but still using):** 569

---

## Why the numbers differ (the reconciliation)

The gap is not error — it is sequence. Churn is a process, not an event:

1. **A subscriber goes silent first** (Network sees it — 23.6%). They stop using the
   service but are still on the books and may still be paying.
2. **Then they stop paying** (Billing sees it — 15.3%). The past-due period trips.
3. **Finally they formally cancel** (Marketing sees it — 13.8%), or the company
   involuntarily disconnects them.

So Network's number is the widest because it catches the earliest signal; Marketing's is
narrowest because it only catches the final, confirmed step. Each team is looking at a
different point in the same funnel.

**The 2.5% all-three overlap** is the hard core — subscribers who are silent, delinquent,
AND formally cancelled. Everyone agrees these have churned. The other ~35% who trip only
one or two signals are where retention effort should focus, because they haven't fully
left yet.

---

## The three headline findings

### 1. Churn is a range, not a number
Reporting a single churn rate to the board hides a 9.8-point spread. The recommended
headline is 13.81% (explicit, most conservative), with payment-lapse and no-usage reported
as leading indicators — not competing headlines.

### 2. 569 subscribers are cancelled but still using the network
That is 41% of the explicit-churn population still consuming service. This is either a
provisioning lag (service not cut after cancellation) or uncaptured reactivation. Both are
revenue-relevant: the company may be giving away service, or under-counting active lines.

### 3. Involuntary churn should not be in win-back budgets
Of 1,392 raw cancellations, 451 (32%) are involuntary disconnects (non-payment). These are
a collections problem, not a satisfaction problem. Targeting them with retention offers
wastes budget. The `churn_type` column keeps them separable.

---

## Data quality issues surfaced (for the client to fix at source)

| Issue | Count | Recommendation |
|---|---|---|
| Cancelled subscribers still using network | 569 | Fix provisioning/billing sync — cut service on cancel |
| Usage mediation replays | 2,427 | Make mediation idempotent |
| SIM-swap duplicate subscriber rows | 50 | Assign new subscriber IDs on SIM swap |
| Unresolved support tickets | 506 | Operational — clear backlog |

---

## What I fixed vs what the client must fix

**Fixed in the pipeline:** SIM-swap dedup, usage replay dedup, three-way churn
classification, reactivation flagging, voluntary/involuntary separation.

**Client must fix at source:** the provisioning-vs-billing desync (569 lines), the
mediation replay problem, and SIM-swap ID reuse. The warehouse can flag these; only the
source systems can cure them.
