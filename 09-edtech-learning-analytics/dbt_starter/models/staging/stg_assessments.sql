select
    assessment_attempt_id, enrollment_id, student_id, course_id,
    assessment_type, score, pass_threshold, is_passed, attempt_status,
    submitted_at, graded_at,
    case when attempt_status = 'submitted' then true else false end as is_ungraded
from {{ source("raw", "raw_assessments") }}
