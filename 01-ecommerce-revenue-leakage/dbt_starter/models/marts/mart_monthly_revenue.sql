with orders as (
    select * from {{ ref("int_orders_enriched") }}
),
refunds_by_month as (
    select refund_month, sum(refund_amount_usd) as refunds_in_month
    from {{ ref("stg_refunds") }}
    group by refund_month
)
select
    date_trunc('month', o.created_at) as report_month,
    count(*) as total_orders,
    -- Gross bookings (Finance's optimistic number)
    sum(o.order_amount_usd) as gross_bookings_usd,
    -- Leakage lines
    sum(case when o.revenue_classification = 'cancelled_unpaid' then o.order_amount_usd else 0 end) as cancelled_unpaid_usd,
    sum(case when o.revenue_classification = 'unpaid_open' then o.order_amount_usd else 0 end) as unpaid_open_usd,
    sum(case when o.revenue_classification = 'paid_but_cancelled' then o.captured_usd else 0 end) as paid_but_cancelled_usd,
    sum(case when o.had_duplicate_charge then o.order_amount_usd else 0 end) as duplicate_charge_exposure_usd,
    -- Captured cash (deduped)
    sum(o.captured_usd) as captured_cash_usd,
    -- Refunds recognized in the order's month
    sum(o.refund_usd) as refunds_usd,
    -- Net revenue
    sum(o.net_revenue_usd) as net_revenue_usd,
    sum(o.gateway_fee_usd) as gateway_fees_usd,
    -- The gap
    sum(o.order_amount_usd) - sum(o.net_revenue_usd) as bookings_to_net_gap_usd,
    round((sum(o.order_amount_usd) - sum(o.net_revenue_usd)) * 100.0 / nullif(sum(o.order_amount_usd),0), 2) as gap_pct
from orders o
group by date_trunc('month', o.created_at)
order by report_month
