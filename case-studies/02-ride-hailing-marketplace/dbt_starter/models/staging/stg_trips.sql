with source as (
    select * from {{ source('raw', 'raw_trips') }}
)

select
    trip_id,
    rider_id,
    driver_id,
    city,
    product,
    trip_status,
    cancel_reason,
    gross_fare,
    surge_multiplier,
    currency,
    is_fraud_flagged,
    pickup_lat,
    pickup_lon,
    dropoff_lat,
    dropoff_lon,
    requested_at,
    accepted_at,
    started_at,
    ended_at,

    -- Derived classifications
    case
        when trip_status = 'completed' and is_fraud_flagged = false then 'clean_completed'
        when trip_status = 'completed' and is_fraud_flagged = true then 'fraud_completed'
        when trip_status = 'cancelled' and gross_fare > 0 then 'billed_cancellation'
        when trip_status = 'cancelled' and gross_fare = 0 then 'zero_fare_cancellation'
    end as trip_classification,

    case
        when trip_status = 'completed' and is_fraud_flagged = false then gross_fare
        else 0
    end as clean_revenue_fare,

    case
        when trip_status = 'cancelled' and gross_fare > 0 then gross_fare
        else 0
    end as cancellation_fee_amount
from source
