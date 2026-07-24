# Source-to-Target Map — E-Commerce Revenue Leakage

Maps every column from RAW source tables through staging, intermediate, and marts.
Documents what changed, what was added, and why.

---

## RAW_ORDERS → stg_orders

| Source Column | Staging Column | Type | Transformation | Notes |
|---|---|---|---|---|
| ORDER_ID | order_id | NUMBER | Passthrough | PK. Verified unique + not_null. |
| CUSTOMER_ID | customer_id | NUMBER | Passthrough | |
| ORDER_STATUS | order_status | VARCHAR | Passthrough | placed/confirmed/completed/cancelled. Unreliable — do not gate revenue on it. |
| ORDER_AMOUNT | order_amount | NUMBER(12,2) | Passthrough | Local currency. |
| CURRENCY | currency | VARCHAR | Passthrough | USD/GBP/EUR. |
| ORDER_AMOUNT + CURRENCY | order_amount_usd | NUMBER | **Derived** | Converted: GBP×1.27, EUR×1.08, USD×1.0. |
| CREATED_AT | created_at | TIMESTAMP_NTZ | Passthrough | |
| UPDATED_AT | updated_at | TIMESTAMP_NTZ | Passthrough | 20 rows precede created_at. |
| — | has_invalid_timestamp | BOOLEAN | **Derived** | true when updated_at < created_at (20 rows). |

**Grain:** 1 row per order. **Rows:** 10,000 in, 10,000 out. **Issues:** 20 invalid timestamps flagged.

---

## RAW_PAYMENTS → stg_payments

| Source Column | Staging Column | Type | Transformation | Notes |
|---|---|---|---|---|
| PAYMENT_ID | payment_id | NUMBER | Passthrough | PK. Unique per attempt. |
| ORDER_ID | order_id | NUMBER | Passthrough | FK to orders. |
| PAYMENT_STATUS | payment_status | VARCHAR | Passthrough | succeeded (9,040) / failed (1,314). |
| AMOUNT | amount | NUMBER(12,2) | Passthrough | |
| CURRENCY | currency | VARCHAR | Passthrough | |
| AMOUNT + CURRENCY | amount_usd | NUMBER | **Derived** | Converted to USD. |
| GATEWAY_FEE | gateway_fee | NUMBER(12,2) | Passthrough | 0 on failures. |
| GATEWAY_FEE + CURRENCY | gateway_fee_usd | NUMBER | **Derived** | Converted to USD. |
| ATTEMPTED_AT | attempted_at | TIMESTAMP_NTZ | Passthrough | |
| PROCESSED_AT | processed_at | TIMESTAMP_NTZ | Passthrough | Null on 1,314 failed attempts. |
| — | succeeded_per_order | NUMBER | **Derived** | Count of succeeded payments per order. |
| — | is_duplicate_charge | BOOLEAN | **Derived** | true when >1 succeeded (121 orders). |
| — | is_primary_record | BOOLEAN | **Derived** | First succeeded per order + all failed. Use for revenue. |

**Grain:** 1 row per payment attempt (no rows dropped). **Rows:** 10,354 in, 10,354 out.
**Issues:** 121 double-charges flagged.

---

## RAW_REFUNDS → stg_refunds

| Source Column | Staging Column | Type | Transformation | Notes |
|---|---|---|---|---|
| REFUND_ID | refund_id | NUMBER | Passthrough | PK. |
| ORDER_ID | order_id | NUMBER | Passthrough | FK to orders. |
| PAYMENT_ID | payment_id | NUMBER | Passthrough | FK to payments (all valid). |
| REFUND_AMOUNT | refund_amount | NUMBER(12,2) | Passthrough | Can be partial (334 of 979). |
| CURRENCY | currency | VARCHAR | Passthrough | |
| REFUND_AMOUNT + CURRENCY | refund_amount_usd | NUMBER | **Derived** | Converted to USD. |
| REFUND_REASON | refund_reason | VARCHAR | Passthrough | 5 reasons, even spread. |
| REFUND_STATUS | refund_status | VARCHAR | Passthrough | all completed. |
| REQUESTED_AT | requested_at | TIMESTAMP_NTZ | Passthrough | |
| PROCESSED_AT | processed_at | TIMESTAMP_NTZ | Passthrough | 48% in a later month than the order. |
| — | refund_month | DATE | **Derived** | date_trunc month of processed_at. Supports cash-basis view. |

**Grain:** 1 row per refund. **Rows:** 979 in, 979 out. **Issues:** 468 cross-month refunds surfaced.

---

## RAW_SHIPPING → stg_shipping

| Source Column | Staging Column | Type | Transformation | Notes |
|---|---|---|---|---|
| SHIPMENT_ID | shipment_id | NUMBER | Passthrough | PK. |
| ORDER_ID | order_id | NUMBER | Passthrough | FK. One shipment per order. |
| CARRIER | carrier | VARCHAR | Passthrough | 4 carriers, even. |
| SHIPPING_COST | shipping_cost | NUMBER(12,2) | Passthrough | |
| STATUS | status | VARCHAR | Passthrough | delivered (7,460) / in_transit (1,093). |
| SHIPPED_AT | shipped_at | TIMESTAMP_NTZ | Passthrough | 637 nulls (carrier timeout). |
| DELIVERED_AT | delivered_at | TIMESTAMP_NTZ | Passthrough | 456 nulls. |
| — | missing_ship_date | BOOLEAN | **Derived** | true when shipped_at null (637). |
| — | missing_delivery_date | BOOLEAN | **Derived** | true when delivered_at null (456). |

**Grain:** 1 row per shipment. **Rows:** 8,553 in, 8,553 out. **Issues:** missing timestamps flagged.

---

## Intermediate + Marts

| Model | Grain | Purpose |
|---|---|---|
| int_orders_enriched | 1 row/order | Joins all 4 staging models; derives revenue_classification + net_revenue_usd |
| mart_revenue | 1 row/order | Finance-ready order-grain fact table |
| mart_monthly_revenue | 1 row/month | Bookings-to-net reconciliation bridge (12 months) |

**revenue_classification values:** recognized, paid_but_cancelled, paid_fully_refunded,
cancelled_unpaid, unpaid_open.