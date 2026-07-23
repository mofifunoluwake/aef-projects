with source as (
    select * from {{ source('raw', 'raw_payments') }}
),

-- Flag duplicate captured payments per trip (210 trips have 2 captures)
captured_ranked as (
    select
        *,
        case
            when payment_status = 'captured' then
                row_number() over (
                    partition by trip_id, payment_status
                    order by captured_at asc
                )
            else 1
        end as capture_rank,
        count(case when payment_status = 'captured' then 1 end) over (
            partition by trip_id
        ) as captures_per_trip
    from source
)

select
    payment_id,
    trip_id,
    rider_id,
    payment_status,
    amount,
    currency,
    payment_method,
    processor_fee,
    attempted_at,
    captured_at,
    captures_per_trip,
    case when captures_per_trip > 1 then true else false end as is_duplicate_capture,
    -- Keep only the first capture per trip for revenue calculations
    case
        when payment_status = 'captured' and capture_rank = 1 then true
        when payment_status = 'failed' then true
        else false
    end as is_primary_record
from captured_ranked
