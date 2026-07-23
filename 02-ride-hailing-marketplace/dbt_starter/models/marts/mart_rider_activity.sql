-- One row per rider. Exposes multiple "active rider" definitions side by side.
-- Window anchored to the latest trip in the dataset, not current_timestamp().

with riders as (
    select * from {{ ref('stg_riders') }}
),

data_boundary as (
    select max(requested_at) as max_trip_date
    from {{ ref('int_trips_enriched') }}
),

trip_stats as (
    select
        rider_id,
        count(*) as total_trips_requested,
        sum(case when trip_status = 'completed' then 1 else 0 end) as completed_trips,
        sum(case when trip_classification = 'clean_completed' then 1 else 0 end) as clean_completed_trips,
        sum(case when trip_classification = 'fraud_completed' then 1 else 0 end) as fraud_completed_trips,
        sum(case when trip_status = 'cancelled' then 1 else 0 end) as cancelled_trips,

        sum(gross_fare_usd) as total_gross_fare_usd,
        sum(clean_revenue_fare_usd) as total_clean_revenue_usd,
        sum(captured_amount_usd) as total_captured_usd,

        min(requested_at) as first_trip_at,
        max(requested_at) as last_trip_at,
        max(case when trip_status = 'completed' then requested_at end) as last_completed_at,
        max(case when trip_classification = 'clean_completed' then requested_at end) as last_clean_completed_at
    from {{ ref('int_trips_enriched') }}
    group by rider_id
)

select
    r.rider_id,
    r.home_city,
    r.account_status,
    r.signup_at,
    r.is_referred,

    coalesce(ts.total_trips_requested, 0) as total_trips_requested,
    coalesce(ts.completed_trips, 0) as completed_trips,
    coalesce(ts.clean_completed_trips, 0) as clean_completed_trips,
    coalesce(ts.fraud_completed_trips, 0) as fraud_completed_trips,
    coalesce(ts.cancelled_trips, 0) as cancelled_trips,

    coalesce(ts.total_gross_fare_usd, 0) as total_gross_fare_usd,
    coalesce(ts.total_clean_revenue_usd, 0) as total_clean_revenue_usd,
    coalesce(ts.total_captured_usd, 0) as total_captured_usd,

    ts.first_trip_at,
    ts.last_trip_at,

    -- ============================================================
    -- FOUR ACTIVE RIDER DEFINITIONS (side by side)
    -- Window anchored to latest trip date in the dataset
    -- ============================================================

    -- Definition 1: CRM flag (Growth's default — misleading)
    case when r.account_status = 'active' then true else false end as is_active_crm,

    -- Definition 2: Requested any trip in trailing 30 days
    case
        when ts.last_trip_at >= dateadd('day', -30, db.max_trip_date)
        then true else false
    end as is_active_requested_30d,

    -- Definition 3: Completed any trip in trailing 30 days
    case
        when ts.last_completed_at >= dateadd('day', -30, db.max_trip_date)
        then true else false
    end as is_active_completed_30d,

    -- Definition 4: Completed a non-fraud trip in trailing 30 days (our recommended)
    case
        when ts.last_clean_completed_at >= dateadd('day', -30, db.max_trip_date)
        then true else false
    end as is_active_clean_30d

from riders r
cross join data_boundary db
left join trip_stats ts on r.rider_id = ts.rider_id
