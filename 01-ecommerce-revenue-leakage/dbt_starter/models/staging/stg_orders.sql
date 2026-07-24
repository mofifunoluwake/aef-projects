with source as (
    select * from {{ source("raw", "raw_orders") }}
)
select
    order_id,
    customer_id,
    order_status,
    order_amount,
    currency,
    order_amount * case currency when 'GBP' then 1.27 when 'EUR' then 1.08 else 1.0 end as order_amount_usd,
    created_at,
    updated_at,
    case when updated_at < created_at then true else false end as has_invalid_timestamp
from source
