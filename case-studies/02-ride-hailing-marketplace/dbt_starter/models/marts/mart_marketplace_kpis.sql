-- Monthly marketplace KPIs + the reconciliation bridge.
-- This is the model that explains the 8-12% GMV-to-net gap.

with trips as (
    select * from {{ ref('int_trips_enriched') }}
),

monthly as (
    select
        date_trunc('month', requested_at) as report_month,

        -- Trip counts
        count(*) as total_trips,
        sum(case when trip_status = 'completed' then 1 else 0 end) as completed_trips,
        sum(case when trip_status = 'cancelled' then 1 else 0 end) as cancelled_trips,
        sum(case when trip_classification = 'clean_completed' then 1 else 0 end) as clean_completed_trips,
        sum(case when trip_classification = 'fraud_completed' then 1 else 0 end) as fraud_completed_trips,
        sum(case when trip_classification = 'billed_cancellation' then 1 else 0 end) as billed_cancellation_trips,
        sum(case when trip_classification = 'zero_fare_cancellation' then 1 else 0 end) as zero_fare_cancellation_trips,

        -- Rates
        round(sum(case when trip_status = 'completed' then 1 else 0 end) * 100.0 / count(*), 2) as completion_rate_pct,
        round(sum(case when trip_classification = 'fraud_completed' then 1 else 0 end) * 100.0
            / nullif(sum(case when trip_status = 'completed' then 1 else 0 end), 0), 2) as fraud_rate_pct,

        -- ============================================================
        -- THE RECONCILIATION BRIDGE (GMV to Net Revenue)
        -- ============================================================

        -- Line 1: Growth's GMV (all gross fares, every trip that had a fare)
        sum(gross_fare_usd) as gmv_usd,

        -- Line 2: SUBTRACT zero-fare cancellations (no fare, but counted in trip volume)
        -- These contribute $0 to GMV, so this line is always 0 in dollar terms
        -- but matters for trip-count reconciliation
        sum(case when trip_classification = 'zero_fare_cancellation' then gross_fare_usd else 0 end) as zero_fare_cancel_usd,

        -- Line 3: SUBTRACT fraud gross fares (trips that happened but revenue reversed)
        sum(case when trip_classification = 'fraud_completed' then gross_fare_usd else 0 end) as fraud_fare_usd,

        -- Line 4: Cancellation fees (real cash collected, separate from clean trip revenue)
        sum(cancellation_fee_usd) as cancellation_fee_revenue_usd,

        -- Line 5: Clean completed trip revenue (the core)
        sum(clean_revenue_fare_usd) as clean_trip_revenue_usd,

        -- Line 6: Actual captured cash (deduped)
        sum(captured_amount_usd) as total_captured_usd,

        -- Line 7: Processor fees
        sum(processor_fee_usd) as total_processor_fees_usd,

        -- Line 8: Net revenue = captured cash - processor fees
        sum(captured_amount_usd) - sum(processor_fee_usd) as net_revenue_usd,

        -- Line 9: Duplicate capture exposure (what would be double-counted without dedup)
        sum(case when had_duplicate_capture then captured_amount_usd else 0 end) as duplicate_capture_exposure_usd,

        -- Line 10: Total incentive spend
        sum(total_incentive_usd) as total_incentive_spend_usd,

        -- Line 11: Incentive spend on fraud trips (cost that should not have been incurred)
        sum(case when is_fraud_flagged and total_incentive_usd is not null
            then total_incentive_usd else 0 end) as fraud_incentive_spend_usd,

        -- Line 12: Take rate = net revenue / GMV
        case
            when sum(gross_fare_usd) > 0
            then round((sum(captured_amount_usd) - sum(processor_fee_usd)) * 100.0 / sum(gross_fare_usd), 2)
            else 0
        end as take_rate_pct,

        -- Line 13: The gap
        sum(gross_fare_usd) - (sum(captured_amount_usd) - sum(processor_fee_usd)) as gmv_to_net_gap_usd,

        case
            when sum(gross_fare_usd) > 0
            then round(
                (sum(gross_fare_usd) - (sum(captured_amount_usd) - sum(processor_fee_usd)))
                * 100.0 / sum(gross_fare_usd), 2)
            else 0
        end as gmv_to_net_gap_pct

    from trips
    group by date_trunc('month', requested_at)
)

select * from monthly
order by report_month
