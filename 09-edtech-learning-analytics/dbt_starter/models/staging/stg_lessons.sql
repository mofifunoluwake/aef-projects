with source as (
    select * from {{ source("raw", "raw_lessons") }}
),
completed_deduped as (
    select *,
        case when lesson_status = 'completed' then
            row_number() over (
                partition by enrollment_id, lesson_number
                order by coalesce(completed_at, started_at) asc
            )
        else 1 end as completion_rank
    from source
)
select
    lesson_event_id, enrollment_id, student_id, course_id,
    lesson_number, lesson_type, lesson_status, device,
    duration_minutes, started_at, completed_at,
    case when completed_at is null and lesson_status = 'completed' then true else false end as missing_completed_at,
    case
        when lesson_status = 'completed' and completion_rank = 1 then true
        when lesson_status = 'started' then true
        else false
    end as is_primary_completion
from completed_deduped
