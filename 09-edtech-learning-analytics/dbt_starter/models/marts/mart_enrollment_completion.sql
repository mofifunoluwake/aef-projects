-- One row per enrolment. Four completion definitions side by side.
with p as (
    select * from {{ ref("int_enrollment_progress") }}
)
select
    enrollment_id, student_id, course_id, plan, locale, category,
    course_title, lesson_count, lessons_completed, pct_lessons_completed,
    assessment_attempts, passed_assessment, best_score, sat_assessment,
    enrollment_status, enrolled_at, last_active_at, last_lesson_at,

    -- Definition 1: Platform status (stale, per brief)
    case when enrollment_status = 'completed' then true else false end as is_complete_platform,

    -- Definition 2: All lessons finished (Curriculum, strict)
    case when lessons_completed >= lesson_count then true else false end as is_complete_all_lessons,

    -- Definition 3: 80%+ lessons finished (Curriculum, lenient)
    case when pct_lessons_completed >= 80 then true else false end as is_complete_80pct_lessons,

    -- Definition 4: Passed assessment (Credentialing)
    case when passed_assessment then true else false end as is_complete_assessment,

    -- Reconciliation categories
    case
        when passed_assessment then 'passed_exam'
        when sat_assessment and not passed_assessment then 'sat_failed_exam'
        when not sat_assessment and pct_lessons_completed >= 80 then 'finished_lessons_no_exam'
        when not sat_assessment and pct_lessons_completed < 80 then 'incomplete'
        else 'other'
    end as completion_category,

    -- "Tested out": passed exam without finishing all lessons
    case when passed_assessment and lessons_completed < lesson_count then true else false end as is_tested_out
from p
