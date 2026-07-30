-- Reconciliation of the four completion definitions + person vs enrolment.
with c as (
    select * from {{ ref("mart_enrollment_completion") }}
)
select
    count(*) as total_enrollments,
    count(distinct student_id) as total_people,

    -- The four definitions (enrolment-grain)
    sum(case when is_complete_platform then 1 else 0 end) as complete_platform,
    sum(case when is_complete_all_lessons then 1 else 0 end) as complete_all_lessons,
    sum(case when is_complete_80pct_lessons then 1 else 0 end) as complete_80pct_lessons,
    sum(case when is_complete_assessment then 1 else 0 end) as complete_assessment,

    -- Rates
    round(sum(case when is_complete_platform then 1 else 0 end) * 100.0 / count(*), 1) as platform_rate_pct,
    round(sum(case when is_complete_all_lessons then 1 else 0 end) * 100.0 / count(*), 1) as all_lessons_rate_pct,
    round(sum(case when is_complete_80pct_lessons then 1 else 0 end) * 100.0 / count(*), 1) as pct80_rate_pct,
    round(sum(case when is_complete_assessment then 1 else 0 end) * 100.0 / count(*), 1) as assessment_rate_pct,

    -- The bridge: where the gap comes from
    sum(case when completion_category = 'passed_exam' then 1 else 0 end) as bridge_passed_exam,
    sum(case when completion_category = 'finished_lessons_no_exam' then 1 else 0 end) as bridge_lessons_no_exam,
    sum(case when completion_category = 'sat_failed_exam' then 1 else 0 end) as bridge_sat_failed,
    sum(case when completion_category = 'incomplete' then 1 else 0 end) as bridge_incomplete,
    sum(case when is_tested_out then 1 else 0 end) as tested_out
from c
