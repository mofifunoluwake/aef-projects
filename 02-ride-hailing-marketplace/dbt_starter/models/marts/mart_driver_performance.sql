-- One row per driver. Trips, earnings, completion rate, incentive totals.
-- Driver paid-incentive totals must reconcile to the payouts ledger (non-negotiable).

with drivers as (
    select * from {{ ref('stg_drivers') }}
),

trip_stats as (
    select
        driver_id,
        count(*) as total_trips,
        sum(case when trip_status = 'completed' then 1 else 0 end) as completed_trips,
        sum(case when trip_status = 'cancelled' then 1 else 0 end) as cancelled_trips,
        sum(case when is_fraud_flagged then 1 else 0 end) as fraud_trips,
        sum(case when trip_classification = 'clean_completed' then 1 else 0 end) as clean_completed_trips,

        -- Earnings
        sum(gross_fare_usd) as gross_fare_usd,
        sum(clean_revenue_fare_usd) as clean_revenue_usd,
        sum(captured_amount_usd) as total_captured_usd,
        sum(processor_fee_usd) as total_processor_fees_usd,

        -- Duplicate captures surfaced (not silently removed)
        sum(case when had_duplicate_capture then captured_amount_usd else 0 end) as duplicate_capture_exposure_usd,

        min(requested_at) as first_trip_at,
        max(requested_at) as last_trip_at
    from {{ ref('int_trips_enriched') }}
    group by driver_id
),

-- Incentive totals from the RAW staging (not the trip-level agg)
-- because driver payouts must reconcile to what was actually paid
incentive_stats as (
    select
        driver_id,
        sum(bonus_amount * case when currency = 'GBP' then 1.27 else 1.0 end) as total_incentive_paid_usd,
        sum(case when is_fraud_trip then bonus_amount * case when currency = 'GBP' then 1.27 else 1.0 end else 0 end) as fraud_trip_incentive_usd,
        sum(case when is_multi_campaign then bonus_amount * case when currency = 'GBP' then 1.27 else 1.0 end else 0 end) as multi_campaign_incentive_usd,
        count(*) as total_incentive_lines,
        count(distinct trip_id) as trips_with_incentives
    from {{ ref('stg_driver_incentives') }}
    group by driver_id
)

select
    d.driver_id,
    d.home_city,
    d.driver_status,
    d.rating,
    d.vehicle_class,
    d.onboarded_at,
    d.is_reonboarded,
    d.onboarding_count,

    -- Trip metrics
    coalesce(ts.total_trips, 0) as total_trips,
    coalesce(ts.completed_trips, 0) as completed_trips,
    coalesce(ts.cancelled_trips, 0) as cancelled_trips,
    coalesce(ts.fraud_trips, 0) as fraud_trips,
    coalesce(ts.clean_completed_trips, 0) as clean_completed_trips,
    case
        when coalesce(ts.total_trips, 0) > 0
        then round(ts.completed_trips * 100.0 / ts.total_trips, 2)
        else 0
    end as completion_rate_pct,
    case
        when coalesce(ts.completed_trips, 0) > 0
        then round(ts.fraud_trips * 100.0 / ts.completed_trips, 2)
        else 0
    end as fraud_rate_pct,

    -- Earnings
    coalesce(ts.gross_fare_usd, 0) as gross_fare_usd,
    coalesce(ts.clean_revenue_usd, 0) as clean_revenue_usd,
    coalesce(ts.total_captured_usd, 0) as total_captured_usd,
    coalesce(ts.total_processor_fees_usd, 0) as total_processor_fees_usd,

    -- Incentives (from payouts ledger — sacred, not restated)
    coalesce(ins.total_incentive_paid_usd, 0) as total_incentive_paid_usd,
    coalesce(ins.fraud_trip_incentive_usd, 0) as fraud_trip_incentive_usd,
    coalesce(ins.multi_campaign_incentive_usd, 0) as multi_campaign_incentive_usd,
    coalesce(ins.total_incentive_lines, 0) as total_incentive_lines,
    coalesce(ins.trips_with_incentives, 0) as trips_with_incentives,

    -- Duplicate capture exposure
    coalesce(ts.duplicate_capture_exposure_usd, 0) as duplicate_capture_exposure_usd,

    ts.first_trip_at,
    ts.last_trip_at

from drivers d
left join trip_stats ts on d.driver_id = ts.driver_id
left join incentive_stats ins on d.driver_id = ins.driver_id
