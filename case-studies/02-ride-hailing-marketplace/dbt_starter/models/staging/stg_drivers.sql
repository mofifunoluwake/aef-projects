with source as (
    select * from {{ source('raw', 'raw_drivers') }}
),

-- Flag duplicate DRIVER_IDs from re-onboarding (30 drivers have 2 rows)
ranked as (
    select
        *,
        row_number() over (
            partition by driver_id
            order by onboarded_at desc
        ) as rn,
        count(*) over (
            partition by driver_id
        ) as onboarding_count
    from source
)

select
    driver_id,
    home_city,
    driver_status,
    rating,
    onboarded_at,
    vehicle_class,
    onboarding_count,
    case when onboarding_count > 1 then true else false end as is_reonboarded
from ranked
where rn = 1  -- keep latest onboarding row per driver
