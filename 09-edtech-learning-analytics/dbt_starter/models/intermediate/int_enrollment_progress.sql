-- One row per enrolment with lesson progress and assessment outcomes rolled up.
with enrollments as (
    select * from {{ ref("stg_students") }}
),
courses as (
    select * from {{ ref("stg_courses") }}
),
lessons as (
    -- Count distinct completed lessons per enrolment (deduped)
    select enrollment_id,
           count(distinct case when lesson_status = 'completed' and is_primary_completion then lesson_number end) as lessons_completed,
           max(coalesce(completed_at, started_at)) as last_lesson_at
    from {{ ref("stg_lessons") }}
    group by enrollment_id
),
assessments as (
    -- Best graded outcome per enrolment
    select enrollment_id,
           count(*) as total_attempts,
           sum(case when is_ungraded then 1 else 0 end) as ungraded_attempts,
           max(case when is_passed then 1 else 0 end) = 1 as ever_passed,
           max(score) as best_score,
           min(submitted_at) as first_attempt_at,
           max(graded_at) as last_graded_at
    from {{ ref("stg_assessments") }}
    group by enrollment_id
)
select
    e.enrollment_id, e.student_id, e.course_id, e.plan, e.locale,
    e.enrollment_status, e.enrolled_at, e.last_active_at,
    c.course_title, c.category, c.lesson_count, c.pass_threshold,
    coalesce(l.lessons_completed, 0) as lessons_completed,
    l.last_lesson_at,
    round(coalesce(l.lessons_completed, 0) * 100.0 / nullif(c.lesson_count, 0), 1) as pct_lessons_completed,
    coalesce(a.total_attempts, 0) as assessment_attempts,
    coalesce(a.ungraded_attempts, 0) as ungraded_attempts,
    coalesce(a.ever_passed, false) as passed_assessment,
    a.best_score,
    a.last_graded_at,
    case when a.enrollment_id is not null then true else false end as sat_assessment
from enrollments e
left join courses c on e.course_id = c.course_id
left join lessons l on e.enrollment_id = l.enrollment_id
left join assessments a on e.enrollment_id = a.enrollment_id
