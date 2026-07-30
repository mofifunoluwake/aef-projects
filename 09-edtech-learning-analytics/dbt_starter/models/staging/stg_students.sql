select
    enrollment_id, student_id, course_id, plan, locale,
    enrollment_status, enrolled_at, last_active_at
from {{ source("raw", "raw_students") }}
