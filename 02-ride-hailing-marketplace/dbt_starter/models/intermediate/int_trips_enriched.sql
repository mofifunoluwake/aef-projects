-- One row per trip, enriched with deduped payment + incentive totals.
-- Downstream marts read from here, not from staging directly.

with trips as (
    select * from {{ ref('stg_trips') }}
),

-- Only primary (deduped) captured payments
payments as (
    select
        trip_id,
        sum(case when is_primary_record and payment_status = 'captured' then amount else 0 end) as captured_amount,
        sum(case when is_primary_record and payment_status = 'captured' then processor_fee else 0 end) as processor_fee,
        max(currency) as payment_currency,
        max(payment_method) as payment_method,
        max(captured_at) as captured_at,
        max(captures_per_trip) as captures_per_trip,
        max(case when is_duplicate_capture then true else false end) as had_duplicate_capture
    from {{ ref('stg_payments') }}
    group by trip_id
),

-- Incentive totals per trip (sum both campaign lines if overlapping)
incentives as (
    select
        trip_id,
        sum(bonus_amount) as total_incentive_amount,
        count(*) as incentive_line_count,
        max(is_multi_campaign) as is_multi_campaign,
        max(is_fraud_trip) as has_fraud_incentive,
        max(currency) as incentive_currency
    from {{ ref('stg_driver_incentives') }}
    group by trip_id
)

select
    t.trip_id,
    t.rider_id,
    t.driver_id,
    t.city,
    t.product,
    t.trip_status,
    t.cancel_reason,
    t.trip_classification,
    t.currency,
    t.is_fraud_flagged,
    t.requested_at,
    t.accepted_at,
    t.started_at,
    t.ended_at,
    t.surge_multiplier,

    -- Fares
    t.gross_fare,
    t.clean_revenue_fare,
    t.cancellation_fee_amount,

    -- Currency conversion (GBP to USD at fixed 1.27 rate)
    case when t.currency = 'GBP' then 1.27 else 1.0 end as fx_rate_to_usd,
    t.gross_fare * case when t.currency = 'GBP' then 1.27 else 1.0 end as gross_fare_usd,
    t.clean_revenue_fare * case when t.currency = 'GBP' then 1.27 else 1.0 end as clean_revenue_fare_usd,
    t.cancellation_fee_amount * case when t.currency = 'GBP' then 1.27 else 1.0 end as cancellation_fee_usd,

    -- Payment data (null if no payment row exists)
    p.captured_amount,
    p.processor_fee,
    p.payment_method,
    p.captured_at,
    p.captures_per_trip,
    p.had_duplicate_capture,
    p.captured_amount * case when t.currency = 'GBP' then 1.27 else 1.0 end as captured_amount_usd,
    p.processor_fee * case when t.currency = 'GBP' then 1.27 else 1.0 end as processor_fee_usd,

    -- Incentive data (null if no incentive for this trip)
    i.total_incentive_amount,
    i.incentive_line_count,
    i.is_multi_campaign,
    i.total_incentive_amount * case when t.currency = 'GBP' then 1.27 else 1.0 end as total_incentive_usd

from trips t
left join payments p on t.trip_id = p.trip_id
left join incentives i on t.trip_id = i.trip_id
