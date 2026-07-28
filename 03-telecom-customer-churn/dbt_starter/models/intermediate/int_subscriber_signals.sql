-- One row per subscriber with all churn signals rolled up as-of 2024-12-31.
with subs as (
    select * from {{ ref("stg_subscribers") }}
),
usage_30d as (
    select subscriber_id,
           count(*) as usage_events_30d,
           sum(usage_units) as usage_units_30d
    from {{ ref("stg_usage") }}
    where usage_date >= '2024-12-01' and usage_date <= '2024-12-31'
    group by subscriber_id
),
usage_all as (
    select subscriber_id,
           max(usage_date) as last_usage_at,
           count(*) as lifetime_usage_events
    from {{ ref("stg_usage") }}
    group by subscriber_id
),
payments as (
    -- Read ALL payment rows (not deduped) so past-due periods are counted correctly
    select subscriber_id,
           sum(case when payment_status = 'past_due' then 1 else 0 end) as past_due_periods,
           sum(case when payment_status = 'failed' then 1 else 0 end) as failed_periods,
           max(case when payment_status = 'past_due' then due_at end) as last_past_due_at
    from {{ source("raw", "raw_payments") }}
    group by subscriber_id
),
tickets as (
    select subscriber_id,
           count(*) as ticket_count,
           sum(case when is_unresolved then 1 else 0 end) as unresolved_tickets
    from {{ ref("stg_support_tickets") }}
    group by subscriber_id
)
select
    s.subscriber_id, s.plan_code, s.region, s.account_status,
    s.autopay_enrolled, s.disconnect_reason, s.activated_at, s.cancelled_at,
    s.is_sim_swapped,
    coalesce(u30.usage_events_30d, 0) as usage_events_30d,
    coalesce(u30.usage_units_30d, 0) as usage_units_30d,
    ua.last_usage_at,
    coalesce(ua.lifetime_usage_events, 0) as lifetime_usage_events,
    coalesce(p.past_due_periods, 0) as past_due_periods,
    coalesce(p.failed_periods, 0) as failed_periods,
    p.last_past_due_at,
    coalesce(t.ticket_count, 0) as ticket_count,
    coalesce(t.unresolved_tickets, 0) as unresolved_tickets
from subs s
left join usage_30d u30 on s.subscriber_id = u30.subscriber_id
left join usage_all ua on s.subscriber_id = ua.subscriber_id
left join payments p on s.subscriber_id = p.subscriber_id
left join tickets t on s.subscriber_id = t.subscriber_id
