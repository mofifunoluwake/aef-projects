-- Reconciliation: how many subscribers each definition flags, and the overlap.
with c as (
    select * from {{ ref("mart_subscriber_churn") }}
)
select
    count(*) as total_subscribers,
    sum(case when is_churned_explicit then 1 else 0 end) as churned_explicit,
    sum(case when is_churned_payment_lapse then 1 else 0 end) as churned_payment_lapse,
    sum(case when is_churned_no_usage then 1 else 0 end) as churned_no_usage,
    -- Union: churned under ANY definition
    sum(case when is_churned_explicit or is_churned_payment_lapse or is_churned_no_usage then 1 else 0 end) as churned_any,
    -- Intersection: churned under ALL three
    sum(case when is_churned_explicit and is_churned_payment_lapse and is_churned_no_usage then 1 else 0 end) as churned_all_three,
    -- Reactivation candidates
    sum(case when is_likely_reactivated then 1 else 0 end) as likely_reactivated,
    -- Rates
    round(sum(case when is_churned_explicit then 1 else 0 end) * 100.0 / count(*), 2) as explicit_rate_pct,
    round(sum(case when is_churned_payment_lapse then 1 else 0 end) * 100.0 / count(*), 2) as payment_lapse_rate_pct,
    round(sum(case when is_churned_no_usage then 1 else 0 end) * 100.0 / count(*), 2) as no_usage_rate_pct
from c
