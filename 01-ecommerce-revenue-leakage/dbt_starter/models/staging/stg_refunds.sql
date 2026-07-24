with source as (
    select * from {{ source("raw", "raw_refunds") }}
)
select
    refund_id,
    order_id,
    payment_id,
    refund_amount,
    currency,
    refund_amount * case currency when 'GBP' then 1.27 when 'EUR' then 1.08 else 1.0 end as refund_amount_usd,
    refund_reason,
    refund_status,
    requested_at,
    processed_at,
    date_trunc('month', processed_at) as refund_month
from source
