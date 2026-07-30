# Source-to-Target Map — EdTech Learning Analytics

Maps every column from RAW source tables through staging, intermediate, and marts.
Documents transformations, derived columns, and dedup logic.

---

## RAW_STUDENTS → stg_students

| Source Column | Staging Column | Type | Transformation | Notes |
|---|---|---|---|---|
| ENROLLMENT_ID | enrollment_id | NUMBER | Passthrough | PK (grain). Verified unique + not_null. |
| STUDENT_ID | student_id | NUMBER | Passthrough | NOT unique — 3,792 people across 12,000 enrolments. |
| COURSE_ID | course_id | NUMBER | Passthrough | FK to courses. |
| PLAN | plan | VARCHAR | Passthrough | free / individual / team. |
| LOCALE | locale | VARCHAR | Passthrough | en-US / en-GB / es-ES / fr-FR. |
| ENROLLMENT_STATUS | enrollment_status | VARCHAR | Passthrough | enrolled / in_progress / completed. Stale — set by overnight job, not trusted. |
| ENROLLED_AT | enrolled_at | TIMESTAMP_NTZ | Passthrough | |
| LAST_ACTIVE_AT | last_active_at | TIMESTAMP_NTZ | Passthrough | Drives active-learner window. |

**Grain:** 1 row per enrolment. **Rows:** 12,000 in/out. No dedup (ENROLLMENT_ID is unique).

---

## RAW_COURSES → stg_courses

| Source Column | Staging Column | Type | Transformation |
|---|---|---|---|
| COURSE_ID | course_id | NUMBER | Passthrough (PK) |
| COURSE_TITLE | course_title | VARCHAR | Passthrough |
| CATEGORY | category | VARCHAR | Passthrough (data/business/design/soft_skills) |
| LESSON_COUNT | lesson_count | NUMBER | Passthrough — drives % lessons rule (4–18) |
| PASS_THRESHOLD | pass_threshold | NUMBER | Passthrough — uniformly 70 |
| IS_ACTIVE | is_active | BOOLEAN | Passthrough |
| CREATED_AT | created_at | TIMESTAMP_NTZ | Passthrough |

**Grain:** 1 row per course. **Rows:** 12 in/out. Clean reference table.

---

## RAW_LESSONS → stg_lessons

| Source Column | Staging Column | Type | Transformation | Notes |
|---|---|---|---|---|
| LESSON_EVENT_ID | lesson_event_id | NUMBER | Passthrough | PK. |
| ENROLLMENT_ID | enrollment_id | NUMBER | Passthrough | FK. |
| STUDENT_ID | student_id | NUMBER | Passthrough | Denormalised. |
| COURSE_ID | course_id | NUMBER | Passthrough | Denormalised. |
| LESSON_NUMBER | lesson_number | NUMBER | Passthrough | Learners move out of order. |
| LESSON_TYPE | lesson_type | VARCHAR | Passthrough | video/reading/interactive/quiz. |
| LESSON_STATUS | lesson_status | VARCHAR | Passthrough | started / completed. |
| DEVICE | device | VARCHAR | Passthrough | web/ios/android. |
| DURATION_MINUTES | duration_minutes | NUMBER | Passthrough | |
| STARTED_AT | started_at | TIMESTAMP_NTZ | Passthrough | |
| COMPLETED_AT | completed_at | TIMESTAMP_NTZ | Passthrough | Null on 4,694 completed (connectivity) + all started. |
| — | missing_completed_at | BOOLEAN | **Derived** | true when completed but timestamp null (4,694). |
| — | is_primary_completion | BOOLEAN | **Derived** | Earliest completion per enrolment+lesson; dedups 2,275 device-switch dupes. |

**Grain:** 1 row per lesson event (no rows dropped). **Rows:** 78,773 in/out. **Issues:** device-switch dupes + dropped timestamps flagged.

---

## RAW_ASSESSMENTS → stg_assessments

| Source Column | Staging Column | Type | Transformation | Notes |
|---|---|---|---|---|
| ASSESSMENT_ATTEMPT_ID | assessment_attempt_id | NUMBER | Passthrough | PK. |
| ENROLLMENT_ID | enrollment_id | NUMBER | Passthrough | FK. |
| STUDENT_ID | student_id | NUMBER | Passthrough | Denormalised. |
| COURSE_ID | course_id | NUMBER | Passthrough | Denormalised. |
| ASSESSMENT_TYPE | assessment_type | VARCHAR | Passthrough | final_exam. |
| SCORE | score | NUMBER | Passthrough | Null while grading (102 rows). |
| PASS_THRESHOLD | pass_threshold | NUMBER | Passthrough | Copied from course (70). |
| IS_PASSED | is_passed | BOOLEAN | Passthrough | Null while grading. |
| ATTEMPT_STATUS | attempt_status | VARCHAR | Passthrough | graded / submitted. |
| SUBMITTED_AT | submitted_at | TIMESTAMP_NTZ | Passthrough | |
| GRADED_AT | graded_at | TIMESTAMP_NTZ | Passthrough | Null while grading. |
| — | is_ungraded | BOOLEAN | **Derived** | true when attempt_status = submitted (102). |

**Grain:** 1 row per attempt (retries retained). **Rows:** 7,486 in/out.
**Status:** graded 7,384 (3,643 passed), submitted 102.

---

## Intermediate + Marts

| Model | Grain | Purpose | Key derived fields |
|---|---|---|---|
| int_enrollment_progress | 1 row/enrolment | Rolls up deduped lessons + best assessment outcome per enrolment | lessons_completed, pct_lessons_completed, passed_assessment, sat_assessment, best_score |
| mart_enrollment_completion | 1 row/enrolment | Four completion definitions side by side + reconciliation category | is_complete_platform, is_complete_all_lessons, is_complete_80pct_lessons, is_complete_assessment, completion_category, is_tested_out |
| mart_completion_summary | 1 row | Reconciliation: four rates + the bridge components + person/enrolment counts | platform_rate_pct, all_lessons_rate_pct, pct80_rate_pct, assessment_rate_pct, bridge_* counts, tested_out |

**completion_category values:** passed_exam, sat_failed_exam, finished_lessons_no_exam,
incomplete, other.

**Lineage:** 4 raw sources → 4 staging views → int_enrollment_progress →
(mart_enrollment_completion → mart_completion_summary).