with source as (
    select * from {{ source("raw", "raw_subscribers") }}
),
ranked as (
    select *,
        row_number() over (partition by subscriber_id order by activated_at desc) as rn,
        count(*) over (partition by subscriber_id) as row_ct
    from source
)
select
    subscriber_id, plan_code, region, account_status, autopay_enrolled,
    disconnect_reason, activated_at, cancelled_at,
    case when row_ct > 1 then true else false end as is_sim_swapped
from ranked
where rn = 1
