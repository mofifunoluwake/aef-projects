select
    order_id,
    customer_id,
    order_status,
    revenue_classification,
    currency,
    order_amount_usd,
    captured_usd,
    refund_usd,
    net_revenue_usd,
    gateway_fee_usd,
    is_paid,
    is_fully_refunded,
    had_duplicate_charge,
    ship_status,
    created_at,
    paid_at
from {{ ref("int_orders_enriched") }}
