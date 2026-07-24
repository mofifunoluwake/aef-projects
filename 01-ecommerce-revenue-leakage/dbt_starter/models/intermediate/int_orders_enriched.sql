with orders as (
    select * from {{ ref("stg_orders") }}
),
payments as (
    select
        order_id,
        sum(case when is_primary_record and payment_status = 'succeeded' then amount_usd else 0 end) as captured_usd,
        sum(case when is_primary_record and payment_status = 'succeeded' then gateway_fee_usd else 0 end) as gateway_fee_usd,
        max(succeeded_per_order) as succeeded_per_order,
        max(case when is_duplicate_charge then 1 else 0 end) = 1 as had_duplicate_charge,
        max(case when payment_status = 'succeeded' then processed_at end) as paid_at
    from {{ ref("stg_payments") }}
    group by order_id
),
refunds as (
    select
        order_id,
        sum(refund_amount_usd) as refund_usd,
        count(*) as refund_count,
        max(processed_at) as last_refund_at
    from {{ ref("stg_refunds") }}
    group by order_id
),
shipping as (
    select
        order_id,
        max(status) as ship_status,
        max(shipped_at) as shipped_at,
        max(missing_ship_date::int) = 1 as missing_ship_date
    from {{ ref("stg_shipping") }}
    group by order_id
)
select
    o.order_id,
    o.customer_id,
    o.order_status,
    o.currency,
    o.order_amount_usd,
    o.created_at,
    o.has_invalid_timestamp,
    coalesce(p.captured_usd, 0) as captured_usd,
    coalesce(p.gateway_fee_usd, 0) as gateway_fee_usd,
    p.paid_at,
    coalesce(p.had_duplicate_charge, false) as had_duplicate_charge,
    case when p.captured_usd > 0 then true else false end as is_paid,
    coalesce(r.refund_usd, 0) as refund_usd,
    coalesce(r.refund_count, 0) as refund_count,
    r.last_refund_at,
    case when coalesce(r.refund_usd,0) >= o.order_amount_usd and r.refund_usd > 0 then true else false end as is_fully_refunded,
    s.ship_status,
    s.shipped_at,
    coalesce(s.missing_ship_date, false) as missing_ship_date,
    -- Revenue recognition: at successful payment, net of refunds
    case
        when p.captured_usd > 0 and o.order_status = 'cancelled' then 'paid_but_cancelled'
        when p.captured_usd > 0 and coalesce(r.refund_usd,0) >= o.order_amount_usd then 'paid_fully_refunded'
        when p.captured_usd > 0 then 'recognized'
        when o.order_status = 'cancelled' then 'cancelled_unpaid'
        else 'unpaid_open'
    end as revenue_classification,
    case when p.captured_usd > 0 then coalesce(p.captured_usd,0) - coalesce(r.refund_usd,0) else 0 end as net_revenue_usd
from orders o
left join payments p on o.order_id = p.order_id
left join refunds r on o.order_id = r.order_id
left join shipping s on o.order_id = s.order_id
