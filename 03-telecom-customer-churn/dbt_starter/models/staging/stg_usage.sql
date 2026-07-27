with source as (
    select * from {{ source("raw", "raw_usage") }}
),
deduped as (
    select *,
        row_number() over (
            partition by subscriber_id, to_date(usage_date), usage_type, usage_units
            order by usage_id
        ) as rn
    from source
)
select usage_id, subscriber_id, usage_type, usage_units, usage_date
from deduped
where rn = 1
