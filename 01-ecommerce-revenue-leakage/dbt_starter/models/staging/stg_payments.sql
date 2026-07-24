with source as (
    select * from {{ source("raw", "raw_payments") }}
),
ranked as (
    select
        *,
        case when payment_status = 'succeeded' then
            row_number() over (partition by order_id, payment_status order by processed_at asc)
        else 1 end as success_rank,
        count(case when payment_status = 'succeeded' then 1 end)
            over (partition by order_id) as succeeded_per_order
    from source
)
select
    payment_id,
    order_id,
    payment_status,
    amount,
    currency,
    amount * case currency when 'GBP' then 1.27 when 'EUR' then 1.08 else 1.0 end as amount_usd,
    payment_method,
    gateway_fee,
    gateway_fee * case currency when 'GBP' then 1.27 when 'EUR' then 1.08 else 1.0 end as gateway_fee_usd,
    attempted_at,
    processed_at,
    succeeded_per_order,
    case when succeeded_per_order > 1 then true else false end as is_duplicate_charge,
    case
        when payment_status = 'succeeded' and success_rank = 1 then true
        when payment_status = 'failed' then true
        else false
    end as is_primary_record
from ranked
