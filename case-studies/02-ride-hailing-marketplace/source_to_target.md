# Source-to-Target Map — Ride-Hailing Marketplace

Maps every column from RAW source tables through to staging models.
Documents what changed, what was added, and why.

---

## RAW_RIDERS → stg_riders

| Source Column | Staging Column | Type | Transformation | Notes |
|---|---|---|---|---|
| RIDER_ID | rider_id | NUMBER | Passthrough | PK. Verified unique + not_null. |
| HOME_CITY | home_city | VARCHAR | Passthrough | 4 cities, roughly even (~25% each). |
| ACCOUNT_STATUS | account_status | VARCHAR | Passthrough | active/dormant/suspended/guest. NOT a usage signal — just CRM state. |
| SIGNUP_AT | signup_at | TIMESTAMP_NTZ | Passthrough | Some predate the trip window. |
| REFERRED_BY | referred_by | NUMBER | Passthrough | NULL for organic signups. |
| — | is_referred | BOOLEAN | **Derived** | `true` if referred_by is not null. 25.2% referral rate. |

**Grain:** 1 row per rider (unchanged from source).
**Row count:** 3,750 in, 3,750 out.
**Issues found:** None.

---

## RAW_DRIVERS → stg_drivers

| Source Column | Staging Column | Type | Transformation | Notes |
|---|---|---|---|---|
| DRIVER_ID | driver_id | NUMBER | **Deduped** | 30 drivers had 2 rows (re-onboarding). Kept latest onboarded_at per driver_id using ROW_NUMBER. |
| HOME_CITY | home_city | VARCHAR | Passthrough (from latest row) | |
| DRIVER_STATUS | driver_status | VARCHAR | Passthrough (from latest row) | active/inactive/deactivated. |
| RATING | rating | NUMBER(4,2) | Passthrough (from latest row) | Range: 3.92–5.00, avg 4.68. |
| ONBOARDED_AT | onboarded_at | TIMESTAMP_NTZ | Passthrough (from latest row) | The most recent onboarding date. |
| VEHICLE_CLASS | vehicle_class | VARCHAR | Passthrough (from latest row) | standard/xl/premium. |
| — | onboarding_count | NUMBER | **Derived** | COUNT(*) per driver_id. 1 = normal, 2 = re-onboarded. |
| — | is_reonboarded | BOOLEAN | **Derived** | `true` if onboarding_count > 1. Preserves visibility into the dedup. |

**Grain:** 1 row per driver (changed from source — source had 1+ rows per driver).
**Row count:** 780 in, 750 out. 30 duplicate rows removed (latest kept, not silently dropped — flagged via is_reonboarded).
**Issues found:** DRIVER_ID reuse on re-onboarding. Documented and resolved.

---

## RAW_TRIPS → stg_trips

| Source Column | Staging Column | Type | Transformation | Notes |
|---|---|---|---|---|
| TRIP_ID | trip_id | NUMBER | Passthrough | PK. Verified unique + not_null. |
| RIDER_ID | rider_id | NUMBER | Passthrough | FK to stg_riders. Relationship tested. |
| DRIVER_ID | driver_id | NUMBER | Passthrough | FK to stg_drivers. Relationship tested. |
| CITY | city | VARCHAR | Passthrough | 4 cities. rivermouth = GBP market. |
| PRODUCT | product | VARCHAR | Passthrough | standard/pool/premium/xl. |
| TRIP_STATUS | trip_status | VARCHAR | Passthrough | completed (12,550) / cancelled (2,450). |
| CANCEL_REASON | cancel_reason | VARCHAR | Passthrough | rider_cancel/no_driver_found/driver_cancel/rider_no_show. NULL on completed. |
| GROSS_FARE | gross_fare | NUMBER(12,2) | Passthrough | The GMV input. Cancellations can have >0 fare (billed) or 0. |
| SURGE_MULTIPLIER | surge_multiplier | NUMBER(5,2) | Passthrough | 1.0 = no surge. |
| CURRENCY | currency | VARCHAR | Passthrough | USD or GBP. Un-normalised. |
| IS_FRAUD_FLAGGED | is_fraud_flagged | BOOLEAN | Passthrough | 395 trips (3.15%). All on completed trips. Flag set after the fact. |
| PICKUP_LAT | pickup_lat | NUMBER(9,6) | Passthrough | Stretch goal: distance/ETA calc. |
| PICKUP_LON | pickup_lon | NUMBER(9,6) | Passthrough | |
| DROPOFF_LAT | dropoff_lat | NUMBER(9,6) | Passthrough | |
| DROPOFF_LON | dropoff_lon | NUMBER(9,6) | Passthrough | |
| REQUESTED_AT | requested_at | TIMESTAMP_NTZ | Passthrough | |
| ACCEPTED_AT | accepted_at | TIMESTAMP_NTZ | Passthrough | |
| STARTED_AT | started_at | TIMESTAMP_NTZ | Passthrough | NULL on 2,450 cancelled trips (expected). |
| ENDED_AT | ended_at | TIMESTAMP_NTZ | Passthrough | NULL on 2,450 cancelled trips (expected). |
| — | trip_classification | VARCHAR | **Derived** | clean_completed / fraud_completed / billed_cancellation / zero_fare_cancellation. |
| — | clean_revenue_fare | NUMBER(12,2) | **Derived** | gross_fare when clean_completed, else 0. |
| — | cancellation_fee_amount | NUMBER(12,2) | **Derived** | gross_fare when billed_cancellation, else 0. |

**Grain:** 1 row per trip (unchanged).
**Row count:** 15,000 in, 15,000 out.
**Issues found:** Fraud flag is retroactive. 1,056 billed cancellations. 602 no_driver_found are always zero-fare.

---

## RAW_PAYMENTS → stg_payments

| Source Column | Staging Column | Type | Transformation | Notes |
|---|---|---|---|---|
| PAYMENT_ID | payment_id | NUMBER | Passthrough | PK. Unique per attempt. |
| TRIP_ID | trip_id | NUMBER | Passthrough | FK to stg_trips. Relationship tested. |
| RIDER_ID | rider_id | NUMBER | Passthrough | |
| PAYMENT_STATUS | payment_status | VARCHAR | Passthrough | captured (13,399) / failed (1,374). |
| AMOUNT | amount | NUMBER(12,2) | Passthrough | Matches trip fare. |
| CURRENCY | currency | VARCHAR | Passthrough | USD or GBP. |
| PAYMENT_METHOD | payment_method | VARCHAR | Passthrough | card/wallet/apple_pay/cash. |
| PROCESSOR_FEE | processor_fee | NUMBER(12,2) | Passthrough | 0 on failed attempts. |
| ATTEMPTED_AT | attempted_at | TIMESTAMP_NTZ | Passthrough | |
| CAPTURED_AT | captured_at | TIMESTAMP_NTZ | Passthrough | NULL on failed attempts. |
| — | captures_per_trip | NUMBER | **Derived** | COUNT of captured rows per trip_id. 1 = normal, 2 = duplicate. |
| — | is_duplicate_capture | BOOLEAN | **Derived** | `true` when captures_per_trip > 1. 210 trips affected. |
| — | is_primary_record | BOOLEAN | **Derived** | `true` for the first capture per trip (by captured_at) + all failed rows. Use this column to filter for revenue calculations. Duplicate rows kept for audit trail. |

**Grain:** 1 row per payment attempt (unchanged — no rows dropped).
**Row count:** 14,773 in, 14,773 out.
**Issues found:** 210 trips have duplicate captured payments (webhook double-logging). 1,775 trips have no payment row at all (1,394 are zero-fare cancels; ~381 have a fare but no payment record).

---

## RAW_DRIVER_INCENTIVES → stg_driver_incentives

| Source Column | Staging Column | Type | Transformation | Notes |
|---|---|---|---|---|
| INCENTIVE_ID | incentive_id | NUMBER | Passthrough | PK. |
| DRIVER_ID | driver_id | NUMBER | Passthrough | FK to stg_drivers. Relationship tested. |
| TRIP_ID | trip_id | NUMBER | Passthrough | FK to stg_trips. Relationship tested. |
| CAMPAIGN | campaign | VARCHAR | Passthrough | 5 campaigns, evenly distributed. |
| BONUS_AMOUNT | bonus_amount | NUMBER(12,2) | Passthrough | Avg ~$2.93–3.13. |
| CURRENCY | currency | VARCHAR | Passthrough | USD or GBP. |
| EARNED_AT | earned_at | TIMESTAMP_NTZ | Passthrough | = trip's ENDED_AT. |
| PAID_AT | paid_at | TIMESTAMP_NTZ | Passthrough | Weekly batch. Avg 10.8 days after earned. Max 37 days. |
| — | payout_lag_days | NUMBER | **Derived** | DATEDIFF(day, earned_at, paid_at). Range: 3–37 days. |
| — | is_fraud_trip | BOOLEAN | **Derived** | Joined from stg_trips. 169 lines ($494.19) on fraud-flagged trips. |
| — | campaign_lines_per_trip | NUMBER | **Derived** | COUNT per trip_id. 1 = single campaign, 2 = overlapping. |
| — | is_multi_campaign | BOOLEAN | **Derived** | `true` when 2+ campaign lines per trip. 1,213 trips affected. |

**Grain:** 1 row per incentive line (unchanged — no rows dropped).
**Row count:** 5,404 in, 5,404 out.
**Issues found:** Multi-campaign overlap (1,213 trips). Incentives on fraud trips (169 lines). Cross-month payout lag (up to 37 days).