# Assumptions Log — Telecom Customer Churn

**Client:** Northwind Cellular
**Consultant:** Analytics Engineering Fellow
**Date:** July 2026
**Dataset:** 10,000 subscribers, seed 42. Fixed observation date: 2024-12-31.

This document records every definitional decision made during the engagement, the
options considered, the decision taken, and the justification. The core problem is that
three teams each define "churn" differently and report different numbers to the CEO. The
goal is not to declare one definition correct, but to compute all three from one model so
each team sees its own number and the business understands the spread.

---

## Decision 1: What counts as "churned"? (the central question)

Three definitions are computed side by side in `mart_subscriber_churn`, each as-of the
fixed observation date 2024-12-31.

| Definition | Owner | Logic | Count | Rate |
|---|---|---|---|---|
| Explicit cancellation | Marketing | account_status = 'cancelled' | 1,381 | 13.81% |
| Payment lapse | Billing | 1+ past-due billing period | 1,530 | 15.30% |
| No usage (30d) | Network | zero usage events Dec 1–31 | 2,357 | 23.57% |

**Decision:** All three are exposed as separate boolean flags. No single definition is
hard-coded as "the" churn rate.

**Justification:** The spread (13.8% to 23.6%, a 9.8-point gap) is the entire reason the
engagement exists. Collapsing to one number would hide the disagreement rather than
resolve it. Only 253 subscribers (2.5%) are flagged by all three definitions — proving
these are three genuinely different populations, not the same people counted three ways.

**Recommended primary for board reporting:** explicit cancellation (Marketing's 13.81%),
because it is the most conservative and legally unambiguous. The other two are exposed as
leading indicators — payment lapse and usage silence often *precede* formal cancellation,
so they are better for early-warning retention programs than for headline reporting.

---

## Decision 2: Payment-lapse threshold — 1 period or 2+?

**Options considered:**
- 1+ past-due period (any lapse)
- 2+ consecutive past-due periods (sustained lapse)

**Decision:** 1+ past-due period.

**Justification:** Profiling showed the distribution is binary — 8,470 subscribers have
zero past-due periods and 1,530 have exactly one. No subscriber has 2+. A 2+ threshold
would flag nobody and produce a meaningless 0% rate. A single past-due period beyond the
grace window is Billing's actual operational churn signal, so 1+ is both correct and the
only threshold the data supports.

---

## Decision 3: How is the "no usage" window defined?

**Options considered:**
- Trailing 30 days from observation date
- Trailing 60 or 90 days
- Calendar month

**Decision:** Zero usage events in the 30 days ending on the observation date (Dec 1–31,
2024).

**Justification:** 30 days is the telecom industry standard for a dormancy signal. The
window is anchored to the fixed observation date (2024-12-31), not the pipeline run date,
so the definition is reproducible. Profiling confirmed the latest usage in the dataset is
2024-12-30 — one day inside the window — so the window meaningfully discriminates between
active and silent lines rather than trivially flagging everyone or no one.

---

## Decision 4: Voluntary vs involuntary churn

**Profiling evidence (of 1,392 raw cancellations):**
- Voluntary: 816
- Involuntary: 451
- Ported out: 125

**Decision:** `churn_type` carries the disconnect reason through to the mart. Involuntary
disconnects (non-payment terminations) are kept distinct from voluntary quits.

**Justification:** Win-back and retention budgets should not target involuntary churners
the same way as voluntary ones — an involuntary disconnect is a collections problem, not a
satisfaction problem. Blending them (as a single "churn" number does) misdirects spend.
Ported-out subscribers left for a competitor and are a separate competitive signal.

---

## Decision 5: Reactivation — cancelled but still using the network

**Finding:** 569 subscribers have account_status = 'cancelled' yet recorded usage events
in the trailing 30 days. That is 41% of the explicit-churn population.

**Decision:** Flagged as `is_likely_reactivated`. Not silently reclassified as active.

**Justification:** This is either a billing-system lag (the cancellation was recorded but
service wasn't cut) or genuine reactivation the billing system never caught. Either way it
is a material data-integrity and revenue-leakage finding — the company may be providing
service to 569 lines it believes are cancelled. Surfacing the flag lets Ops investigate;
silently "fixing" it would bury a real operational problem.

---

## Decision 6: Deduplication

### Subscriber SIM swaps
**Finding:** 10,050 rows for 10,000 subscribers — 50 duplicates from SIM swaps.
**Decision:** In `stg_subscribers`, keep the latest row per SUBSCRIBER_ID by ACTIVATED_AT.
Flag with `is_sim_swapped`. No rows silently dropped.

### Usage mediation replays
**Finding:** 2,427 replay duplicates — same subscriber, date, usage type, and units but a
new USAGE_ID (the mediation system re-emitted records). All USAGE_IDs are technically
unique, so dedup cannot key on the ID.
**Decision:** In `stg_usage`, dedup on the business key (subscriber + date + type + units),
keeping the lowest USAGE_ID. This removes the replays without losing genuine repeat usage.

### Payment periods
**Decision:** For the deduped payment view (`stg_payments`), keep the most authoritative
status per subscriber+billing_period. BUT the payment-lapse churn signal reads all raw
payment rows in the intermediate model, so past-due periods are counted before dedup
collapses them. This separation is deliberate — dedup for the current-state view, raw
counts for the historical churn signal.

---

## Data quality issues found during profiling

| Issue | Count | Severity | Resolution | Source fix needed? |
|---|---|---|---|---|
| SIM-swap duplicate subscribers | 50 | Medium | Deduped, flagged | Yes — assign new IDs on SIM swap |
| Usage mediation replays | 2,427 | High | Deduped on business key | Yes — mediation idempotency |
| Cancelled subs still using network | 569 | High | Flagged as reactivated | Yes — provisioning/billing sync |
| Unresolved support tickets | 506 | Low | Flagged | No — operational backlog |
| Timestamp corruption on load (Py 3.14) | all | High | Fixed via string reload | Yes — pin connector version |

---

## Fixed parameters

| Parameter | Value | Rationale |
|---|---|---|
| Observation date | 2024-12-31 | Fixed per brief; all churn evaluated as-of this date |
| No-usage window | 30 days (Dec 1–31) | Industry-standard dormancy signal |
| Payment-lapse threshold | 1+ past-due period | Only threshold the data supports |
| Subscriber dedup | Latest ACTIVATED_AT | Current state per line |
| Usage dedup | Business key, lowest USAGE_ID | Removes replays, keeps real usage |
| Recommended headline churn | Explicit cancellation (13.81%) | Most conservative, unambiguous |
