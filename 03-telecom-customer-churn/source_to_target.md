# Source-to-Target Map — Telecom Customer Churn

Maps every column from RAW source tables through staging, intermediate, and marts.
Documents transformations, derived columns, and dedup logic.

---

## RAW_SUBSCRIBERS → stg_subscribers

| Source Column | Staging Column | Type | Transformation | Notes |
|---|---|---|---|---|
| SUBSCRIBER_ID | subscriber_id | NUMBER | **Deduped** | 50 SIM-swap dupes collapsed; keep latest ACTIVATED_AT. |
| PLAN_CODE | plan_code | VARCHAR | Passthrough | FK to plans. |
| REGION | region | VARCHAR | Passthrough | |
| ACCOUNT_STATUS | account_status | VARCHAR | Passthrough | active / cancelled. |
| AUTOPAY_ENROLLED | autopay_enrolled | BOOLEAN | Passthrough | |
| DISCONNECT_REASON | disconnect_reason | VARCHAR | Passthrough | voluntary / involuntary / ported_out / null. |
| ACTIVATED_AT | activated_at | TIMESTAMP_NTZ | Passthrough | Dedup ordering key. |
| CANCELLED_AT | cancelled_at | TIMESTAMP_NTZ | Passthrough | Null for active lines. |
| — | is_sim_swapped | BOOLEAN | **Derived** | true when subscriber had >1 raw row (50 subs). |

**Grain:** 1 row per subscriber. **Rows:** 10,050 in, 10,000 out.

---

## RAW_PLANS → stg_plans

| Source Column | Staging Column | Type | Transformation |
|---|---|---|---|
| PLAN_CODE | plan_code | VARCHAR | Passthrough (PK) |
| PLAN_TYPE | plan_type | VARCHAR | Passthrough (prepaid/postpaid) |
| MONTHLY_RECURRING_CHARGE | monthly_recurring_charge | NUMBER | Passthrough |
| DATA_ALLOWANCE_GB | data_allowance_gb | NUMBER | Passthrough |
| CONTRACT_MONTHS | contract_months | NUMBER | Passthrough |

**Grain:** 1 row per plan. **Rows:** 6 in, 6 out. Clean reference table.

---

## RAW_USAGE → stg_usage

| Source Column | Staging Column | Type | Transformation | Notes |
|---|---|---|---|---|
| USAGE_ID | usage_id | NUMBER | Passthrough | Technically unique even on replays. |
| SUBSCRIBER_ID | subscriber_id | NUMBER | Passthrough | FK. |
| USAGE_TYPE | usage_type | VARCHAR | Passthrough | voice / data / sms. |
| USAGE_UNITS | usage_units | NUMBER | Passthrough | |
| USAGE_DATE | usage_date | TIMESTAMP_NTZ | Passthrough | |
| — | (dedup applied) | — | **Deduped** | 2,427 replays removed via business key (subscriber+date+type+units), keep lowest USAGE_ID. |

**Grain:** 1 row per genuine usage event. **Rows:** 207,242 in, ~204,815 out (replays removed).

---

## RAW_PAYMENTS → stg_payments

| Source Column | Staging Column | Type | Transformation | Notes |
|---|---|---|---|---|
| PAYMENT_ID | payment_id | NUMBER | Passthrough (PK) | |
| SUBSCRIBER_ID | subscriber_id | NUMBER | Passthrough | FK. |
| BILLING_PERIOD | billing_period | VARCHAR | Passthrough | |
| AMOUNT_DUE | amount_due | NUMBER | Passthrough | |
| PAYMENT_STATUS | payment_status | VARCHAR | Passthrough | paid / past_due / failed. |
| PAYMENT_METHOD | payment_method | VARCHAR | Passthrough | |
| DUE_AT | due_at | TIMESTAMP_NTZ | Passthrough | |
| PAID_AT | paid_at | TIMESTAMP_NTZ | Passthrough | Null when unpaid. |
| — | (dedup applied) | — | **Deduped** | Latest authoritative status per subscriber+billing_period. Note: churn signal counts raw past-due periods upstream of this dedup. |

**Grain:** 1 row per subscriber+billing_period. **Rows:** 13,521 in.
**Status split:** paid 11,519, past_due 1,530, failed 472.

---

## RAW_SUPPORT_TICKETS → stg_support_tickets

| Source Column | Staging Column | Type | Transformation | Notes |
|---|---|---|---|---|
| TICKET_ID | ticket_id | NUMBER | Passthrough (PK) | |
| SUBSCRIBER_ID | subscriber_id | NUMBER | Passthrough | FK. |
| CATEGORY | category | VARCHAR | Passthrough | |
| CHANNEL | channel | VARCHAR | Passthrough | |
| OPENED_AT | opened_at | TIMESTAMP_NTZ | Passthrough | |
| RESOLVED_AT | resolved_at | TIMESTAMP_NTZ | Passthrough | Null on 506 unresolved. |
| — | is_unresolved | BOOLEAN | **Derived** | true when resolved_at is null. |

**Grain:** 1 row per ticket. **Rows:** 5,111 in.

---

## Intermediate + Marts

| Model | Grain | Purpose |
|---|---|---|
| int_subscriber_signals | 1 row/subscriber | Rolls up usage (30d + lifetime), past-due periods, tickets — all as-of 2024-12-31 |
| mart_subscriber_churn | 1 row/subscriber | Three churn flags + churn_type + reactivation flag |
| mart_churn_summary | 1 row | Reconciliation: counts, union, intersection, rates per definition |

**Derived churn columns in mart_subscriber_churn:**
- `is_churned_explicit` — account_status = 'cancelled'
- `is_churned_payment_lapse` — past_due_periods >= 1
- `is_churned_no_usage` — usage_events_30d = 0
- `churn_type` — voluntary / involuntary / ported_out / not_cancelled
- `is_likely_reactivated` — cancelled but used network in trailing 30d (569 subs)
