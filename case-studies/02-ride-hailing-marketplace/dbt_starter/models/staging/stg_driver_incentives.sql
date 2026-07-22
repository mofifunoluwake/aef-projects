with source as (
    select * from {{ source('raw', 'raw_driver_incentives') }}
),

trip_fraud as (
    select trip_id, is_fraud_flagged
    from {{ source('raw', 'raw_trips') }}
)

select
    i.incentive_id,
    i.driver_id,
    i.trip_id,
    i.campaign,
    i.bonus_amount,
    i.currency,
    i.earned_at,
    i.paid_at,
    datediff('day', i.earned_at, i.paid_at) as payout_lag_days,

    -- Flag incentives on fraud trips (169 lines, $494.19)
    coalesce(tf.is_fraud_flagged, false) as is_fraud_trip,

    -- Flag multi-campaign attribution (1,213 trips have 2 lines)
    count(*) over (partition by i.trip_id) as campaign_lines_per_trip,
    case when count(*) over (partition by i.trip_id) > 1 then true else false end as is_multi_campaign
from source i
left join trip_fraud tf on i.trip_id = tf.trip_id
