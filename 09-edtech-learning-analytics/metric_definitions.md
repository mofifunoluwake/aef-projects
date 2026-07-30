# Business Metric Definitions — EdTech Learning Analytics

Each metric has one definition. Where teams disagree (completion), all competing definitions
are computed and exposed; the recommended default per audience is noted. Reporting grain is
the enrolment (student × course).

| Metric | Definition | Model / Column | Notes |
|---|---|---|---|
| **Completion — all lessons** | lessons_completed >= lesson_count | mart_enrollment_completion.is_complete_all_lessons | 44.2%. Curriculum (strict). The "45%". |
| **Completion — 80% lessons** | pct_lessons_completed >= 80 | mart_enrollment_completion.is_complete_80pct_lessons | 51.0%. Curriculum (lenient). |
| **Completion — assessment** | passed a graded final exam | mart_enrollment_completion.is_complete_assessment | 29.7%. Credentialing. The "30%". Recommended for external/audit. |
| **Completion — platform** | enrollment_status = 'completed' | mart_enrollment_completion.is_complete_platform | 28.1%. Stale source field — not trusted. |
| **Completion rate (enrolment)** | completed enrolments / total enrolments | mart_completion_summary rate columns | Denominator = 12,000 enrolments. |
| **Completion rate (person)** | people who completed >=1 course / total people | derived from student_id rollup | Denominator = 3,792 people. Different number. |
| **Active learner** | any activity in trailing 28 days | derived from last_active_at | 28-day MAU window; 7-day available. |
| **Avg lessons completed** | mean of lessons_completed | int_enrollment_progress | Per enrolment. |
| **Assessment pass rate** | passing graded attempts / graded attempts | stg_assessments | 3,643 / 7,384 graded = 49.3%. |
| **Time-to-complete** | last_lesson_at − enrolled_at | int_enrollment_progress | Falls back to started_at where completed_at null. |
| **Tested out** | passed exam without finishing all lessons | mart_enrollment_completion.is_tested_out | 595. Pulls the gap the other way. |

## Definitional contract

- **Completion is a range, not a scalar.** Any single-number completion report must state
  which definition and which unit (person vs enrolment) it uses.
- **Recommended defaults:** assessment-pass (29.7%) for external/audit reporting where a
  certificate must be defensible; all-lessons (44.2%) for internal engagement reporting.
- **The platform status field is not a source of truth** — it is stale and event-based
  definitions override it.
- **The completion gap runs both ways:** lessons-no-exam learners (1,378) and tested-out
  learners (595) are opposing flows, not one population.