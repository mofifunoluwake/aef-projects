with source as (
    select * from {{ source('raw', 'raw_riders') }}
)

select
    rider_id,
    home_city,
    account_status,
    signup_at,
    referred_by,
    case when referred_by is not null then true else false end as is_referred
from source
