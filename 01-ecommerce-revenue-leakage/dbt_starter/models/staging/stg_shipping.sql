with source as (
    select * from {{ source("raw", "raw_shipping") }}
)
select
    shipment_id,
    order_id,
    carrier,
    shipping_cost,
    status,
    shipped_at,
    delivered_at,
    case when shipped_at is null then true else false end as missing_ship_date,
    case when delivered_at is null then true else false end as missing_delivery_date
from source
