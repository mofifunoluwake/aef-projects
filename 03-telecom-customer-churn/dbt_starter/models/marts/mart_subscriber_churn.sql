-- One row per subscriber. Three churn definitions side by side, as-of 2024-12-31.
-- Marketing = explicit cancel; Billing = payment lapse; Network = no usage 30d.

with signals as (
    select * from {{ ref("int_subscriber_signals") }}
)
select
    subscriber_id, plan_code, region, account_status,
    autopay_enrolled, disconnect_reason, is_sim_swapped,
    usage_events_30d, usage_units_30d, last_usage_at,
    past_due_periods, ticket_count, unresolved_tickets,

    -- Definition 1: Marketing — explicit cancellation
    case when account_status = 'cancelled' then true else false end as is_churned_explicit,

    -- Definition 2: Billing — payment lapse (2+ past-due periods)
    case when past_due_periods >= 1 then true else false end as is_churned_payment_lapse,

    -- Definition 3: Network — no usage in trailing 30 days
    case when coalesce(usage_events_30d, 0) = 0 then true else false end as is_churned_no_usage,

    -- Voluntary vs involuntary (only meaningful for explicit cancels)
    case
        when account_status = 'cancelled' and disconnect_reason = 'voluntary' then 'voluntary'
        when account_status = 'cancelled' and disconnect_reason = 'involuntary' then 'involuntary'
        when account_status = 'cancelled' and disconnect_reason = 'ported_out' then 'ported_out'
        else 'not_cancelled'
    end as churn_type,

    -- Reactivation flag: cancelled on paper but still using the network
    case
        when account_status = 'cancelled' and coalesce(usage_events_30d,0) > 0
        then true else false
    end as is_likely_reactivated
from signals
