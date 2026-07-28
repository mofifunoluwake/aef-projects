# Source-to-Target Map — Ride-Hailing Marketplace

Maps every column from RAW source tables through staging, intermediate, and marts.
Documents what changed, what was added, and why.

---

## RAW_RIDERS → stg_riders

| Source Column | Staging Column | Type | Transformation | Notes |
|---|---|---|---|---|
| RIDER_ID | rider_id | NUMBER | Passthrough | PK. Verified unique + not_null. |
| HOME_CITY | home_city | VARCHAR | Passthrough | 4 cities, ~even. |
| ACCOUNT_STATUS | account_status | VARCHAR | Passthrough | active/dormant/suspended/guest. NOT a usage signal. |
| SIGNUP_AT | signup_at | TIMESTAMP_NTZ | Passthrough | |
| REFERRED_BY | referred_by | NUMBER | Passthrough | Null for organic. |
| — | is_referred | BOOLEAN | **Derived** | true if referred_by not null. 25.2% referral rate. |

**Grain:** 1 row per rider. **Rows:** 3,750 in, 3,750 out. **Issues:** none.

---

## RAW_DRIVERS → stg_drivers

| Source Column | Staging Column | Type | Transformation | Notes |
|---|---|---|---|---|
| DRIVER_ID | driver_id | NUMBER | **Deduped** | 30 drivers had 2 rows (re-onboarding). Keep latest ONBOARDED_AT. |
| HOME_CITY | home_city | VARCHAR | Passthrough (latest row) | |
| DRIVER_STATUS | driver_status | VARCHAR | Passthrough (latest row) | active/inactive/deactivated. |
| RATING | rating | NUMBER(4,2) | Passthrough (latest row) | 3.92–5.00, avg 4.68. |
| ONBOARDED_AT | onboarded_at | TIMESTAMP_NTZ | Passthrough (latest row) | |
| VEHICLE_CLASS | vehicle_class | VARCHAR | Passthrough (latest row) | standard/xl/premium. |
| — | onboarding_count | NUMBER | **Derived** | 1 or 2. |
| — | is_reonboarded | BOOLEAN | **Derived** | true if onboarding_count > 1 (30 drivers). |

**Grain:** 1 row per driver. **Rows:** 780 in, 750 out. **Issues:** DRIVER_ID reuse deduped + flagged.

---

## RAW_TRIPS → stg_trips

| Source Column | Staging Column | Type | Transformation | Notes |
|---|---|---|---|---|
| TRIP_ID | trip_id | NUMBER | Passthrough | PK. |
| RIDER_ID | rider_id | NUMBER | Passthrough | FK to stg_riders (relationship tested). |
| DRIVER_ID | driver_id | NUMBER | Passthrough | FK to stg_drivers (relationship tested). |
| CITY | city | VARCHAR | Passthrough | rivermouth = GBP market. |
| PRODUCT | product | VARCHAR | Passthrough | |
| TRIP_STATUS | trip_status | VARCHAR | Passthrough | completed 12,550 / cancelled 2,450. |
| CANCEL_REASON | cancel_reason | VARCHAR | Passthrough | null on completed. |
| GROSS_FARE | gross_fare | NUMBER(12,2) | Passthrough | The GMV input. |
| SURGE_MULTIPLIER | surge_multiplier | NUMBER(5,2) | Passthrough | |
| CURRENCY | currency | VARCHAR | Passthrough | USD or GBP. |
| IS_FRAUD_FLAGGED | is_fraud_flagged | BOOLEAN | Passthrough | 395 trips, set after the fact. |
| REQUESTED_AT / ACCEPTED_AT / STARTED_AT / ENDED_AT | (same) | TIMESTAMP_NTZ | Passthrough | started/ended null on 2,450 cancels. |
| — | trip_classification | VARCHAR | **Derived** | clean_completed / fraud_completed / billed_cancellation / zero_fare_cancellation. |
| — | clean_revenue_fare | NUMBER | **Derived** | gross_fare when clean_completed, else 0. |
| — | cancellation_fee_amount | NUMBER | **Derived** | gross_fare when billed_cancellation, else 0. |

**Grain:** 1 row per trip. **Rows:** 15,000 in/out. **Issues:** retroactive fraud flag, 1,056 billed cancellations.

---

## RAW_PAYMENTS → stg_payments

| Source Column | Staging Column | Type | Transformation | Notes |
|---|---|---|---|---|
| PAYMENT_ID | payment_id | NUMBER | Passthrough | PK. |
| TRIP_ID | trip_id | NUMBER | Passthrough | FK to stg_trips. |
| RIDER_ID | rider_id | NUMBER | Passthrough | |
| PAYMENT_STATUS | payment_status | VARCHAR | Passthrough | captured 13,399 / failed 1,374. |
| AMOUNT | amount | NUMBER(12,2) | Passthrough | |
| CURRENCY | currency | VARCHAR | Passthrough | |
| PAYMENT_METHOD | payment_method | VARCHAR | Passthrough | |
| PROCESSOR_FEE | processor_fee | NUMBER(12,2) | Passthrough | |
| ATTEMPTED_AT / CAPTURED_AT | (same) | TIMESTAMP_NTZ | Passthrough | captured_at null on failures. |
| — | captures_per_trip | NUMBER | **Derived** | 1 = normal, 2 = duplicate (210 trips). |
| — | is_duplicate_capture | BOOLEAN | **Derived** | true when captures_per_trip > 1. |
| — | is_primary_record | BOOLEAN | **Derived** | First capture per trip + all failed. Use for revenue. |

**Grain:** 1 row per payment attempt (no rows dropped). **Rows:** 14,773 in/out. **Issues:** 210 duplicate captures flagged.

---

## RAW_DRIVER_INCENTIVES → stg_driver_incentives

| Source Column | Staging Column | Type | Transformation | Notes |
|---|---|---|---|---|
| INCENTIVE_ID | incentive_id | NUMBER | Passthrough | PK. |
| DRIVER_ID | driver_id | NUMBER | Passthrough | FK to stg_drivers. |
| TRIP_ID | trip_id | NUMBER | Passthrough | FK to stg_trips. |
| CAMPAIGN | campaign | VARCHAR | Passthrough | 5 campaigns, even. |
| BONUS_AMOUNT | bonus_amount | NUMBER(12,2) | Passthrough | |
| CURRENCY | currency | VARCHAR | Passthrough | |
| EARNED_AT / PAID_AT | (same) | TIMESTAMP_NTZ | Passthrough | |
| — | payout_lag_days | NUMBER | **Derived** | 3–37 days. |
| — | is_fraud_trip | BOOLEAN | **Derived** | Joined from trips. 169 lines ($494). |
| — | campaign_lines_per_trip | NUMBER | **Derived** | 1 or 2. |
| — | is_multi_campaign | BOOLEAN | **Derived** | true when 2+ (1,213 trips). |

**Grain:** 1 row per incentive line (no rows dropped). **Rows:** 5,404 in/out. **Issues:** multi-campaign overlap + fraud-trip incentives flagged.

---

## Intermediate + Marts

| Model | Grain | Purpose | Key derived fields |
|---|---|---|---|
| int_trips_enriched | 1 row/trip | Joins trips + deduped payments + incentives; applies currency conversion | gross_fare_usd, clean_revenue_fare_usd, captured_amount_usd, total_incentive_usd, fx_rate_to_usd |
| mart_driver_performance | 1 row/driver | Driver Ops view; incentives reconcile to payouts ledger | total_trips, completion_rate_pct, fraud_rate_pct, total_incentive_paid_usd, duplicate_capture_exposure_usd |
| mart_rider_activity | 1 row/rider | 4 active-rider definitions side by side | is_active_crm, is_active_requested_30d, is_active_completed_30d, is_active_clean_30d |
| mart_marketplace_kpis | 1 row/month | GMV-to-net reconciliation bridge (12 months) | gmv_usd, fraud_fare_usd, cancellation_fee_revenue_usd, net_revenue_usd, take_rate_pct, gmv_to_net_gap_usd, gmv_to_net_gap_pct |

**Lineage:** 5 raw sources → 5 staging views → int_trips_enriched → (mart_driver_performance,
mart_rider_activity, mart_marketplace_kpis). stg_riders and stg_drivers also feed their
respective marts directly.