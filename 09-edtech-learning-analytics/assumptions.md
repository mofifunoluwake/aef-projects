# Assumptions Log — EdTech Learning Analytics

**Client:** Lumen Lyceum
**Consultant:** Joy Rereloluwa Ogunmodede
**Date:** July 2026
**Dataset:** 12,000 enrolments, seed 42. Reporting grain: enrolment (student × course).

This document records every definitional decision made during the engagement, the options
considered, the decision taken, and the justification. The core problem is that Curriculum
and Credentialing disagree on what "course completion" means, producing a ~15-point gap in
the headline number. The goal is not to declare one definition correct, but to compute all
of them from one model so each team sees its own number and the business understands the
spread.

---

## Decision 1: What is a "completed" course? (the central question)

Four definitions are computed side by side in `mart_enrollment_completion`, each as an
explicit boolean flag.

| Definition | Owner | Logic | Count | Rate |
|---|---|---|---|---|
| 80%+ lessons finished | Curriculum (lenient) | pct_lessons_completed >= 80 | 6,122 | 51.0% |
| All lessons finished | Curriculum (strict) | lessons_completed >= lesson_count | 5,300 | 44.2% |
| Assessment passed | Credentialing | passed_assessment = true | 3,568 | 29.7% |
| Platform status | Source system | enrollment_status = 'completed' | 3,369 | 28.1% |

**Decision:** All four are exposed as separate flags. No single definition is baked in as
"the" completion rate.

**Justification:** The gap between the strict-lessons number (44.2%) and the assessment
number (29.7%) is 14.5 points — the ~15-point discrepancy the VP of Learning needs
explained. Collapsing to one number would hide the disagreement. The platform status field
(28.1%) is exposed too but flagged as unreliable — it is set by an overnight job and
disagrees with the underlying events.

**Recommended primary for external/audit reporting:** assessment passed (Credentialing's
29.7%), because a certificate must mean something to an employer. **Recommended for
internal engagement reporting:** all-lessons (Curriculum's 44.2%), because it measures what
learners actually consumed. The two serve different audiences and both are legitimate.

---

## Decision 2: What is the unit of analysis — person or enrolment?

**Finding:** 12,000 enrolments but only 3,792 distinct people (~3.2 enrolments each).

**Decision:** The mart grain is the enrolment (one row per student × course). Person-level
rollups are derived on top (total_people in the summary), never baked into the base grain.

**Justification:** Enrolment is the grain at which completion actually happens — a person
doesn't "complete" in the abstract, they complete a specific course. Reporting "% of
enrolments completed" and "% of people who completed at least one course" are both valid but
very different numbers; keeping the base grain at enrolment lets either be computed without
losing information. Collapsing to person-grain too early would make per-course completion
impossible to recover.

---

## Decision 3: What is an "active learner"?

**Options considered:** active in last 7 / 28 days; per enrolment vs per person.

**Decision:** Active = any recorded activity (lesson or assessment) in the trailing 28 days
from the enrolment's last_active_at, measured per enrolment, with a person-level rollup
available. 28 days is the reporting default; 7-day is available as a tighter engagement
signal.

**Justification:** 28 days is the standard monthly-active window for self-paced learning,
where learners work in bursts rather than daily. Per-enrolment is the base measure because a
person can be active in one course and dormant in another; the person-level "active in any
course" rollup is the retention headline.

---

## Decision 4: The learner who finished lessons but never sat the exam (or failed it)

**Finding:** 1,378 enrolments finished 80%+ of lessons but never sat the exam; 1,520 sat and
failed; 595 "tested out" (passed the exam without finishing all lessons).

**Decision:** These are not forced into a single bucket. The `completion_category` column
places every enrolment into exactly one of: passed_exam, sat_failed_exam,
finished_lessons_no_exam, incomplete. The `is_tested_out` flag separately marks the 595 who
passed without full lessons.

**Justification:** This is the heart of the reconciliation. Curriculum counts the 1,378
lessons-no-exam learners as complete; Credentialing does not. The 595 tested-out learners
run the other way — Credentialing counts them, strict-Curriculum does not. The gap runs in
both directions, so a single flag cannot represent it. Exposing the categories lets each
stakeholder see exactly which population separates their number from the other's.

---

## Decision 5: Duplicate lesson events and ungraded assessment attempts

### Duplicate lesson completions (device switches)
**Finding:** 2,275 enrolment+lesson pairs logged as completed more than once (learner
resumed on another device).
**Decision:** In `stg_lessons`, keep the earliest completion per enrolment+lesson_number
(by completed_at, falling back to started_at), flagged via `is_primary_completion`. Completed
lessons are counted distinct on lesson_number in the intermediate model. No rows dropped.
**Justification:** Counting both device rows would overstate lesson progress and inflate the
lessons-based completion number. Distinct-on-lesson_number is the correct dedup because the
learner completed the *lesson* once, regardless of how many devices logged it.

### Ungraded assessment attempts
**Finding:** 102 attempts are still `submitted` (null score, not yet graded).
**Decision:** Ungraded attempts are flagged (`is_ungraded`) and excluded from pass/fail
completion — an enrolment is only "assessment complete" if it has a graded, passing attempt.
**Justification:** A submitted-but-ungraded attempt is mid-flight; treating it as either pass
or fail would be wrong. Excluding it from the completion flag (while keeping it visible)
avoids both over- and under-counting.

### Retried attempts
**Decision:** An enrolment with multiple attempts is "passed" if *any* graded attempt passed
(best outcome wins). All attempts are retained in staging for audit.
**Justification:** A learner who failed twice then passed has demonstrated mastery — the pass
is what counts. Counting each attempt separately would distort the pass rate.

---

## Decision 6: Dropped lesson end-timestamps

**Finding:** 4,694 completed lessons have a null COMPLETED_AT (player lost connectivity).

**Decision:** Flagged via `missing_completed_at`. For time-to-complete calculations, fall
back to STARTED_AT; the lesson still counts as completed (LESSON_STATUS is authoritative for
completion, not the timestamp).

**Justification:** A missing end-timestamp is a telemetry gap, not evidence the lesson wasn't
finished. Dropping these would understate completion; the fallback preserves the count while
flagging the data-quality issue for source-side fixing.

---

## Data quality issues found during profiling

| Issue | Count | Severity | Resolution | Source fix needed? |
|---|---|---|---|---|
| Duplicate lesson completions (device switch) | 2,275 | High | Deduped on enrolment+lesson, flagged | Yes — idempotent event logging |
| Dropped lesson end-timestamps | 4,694 | Medium | Flagged, fall back to started_at | Yes — player telemetry reliability |
| Ungraded assessment attempts | 102 | Low | Flagged, excluded from completion | No — normal grading lag |
| Stale platform status field | — | Medium | Exposed but not trusted; events are authoritative | Yes — fix the overnight status job |
| Person-vs-enrolment ambiguity | 12,000 vs 3,792 | High | Enrolment grain + person rollup | No — modeling decision |
| Timestamp corruption on load (Py 3.14) | all | High | Fixed via string reload | Yes — pin connector version |

---

## Fixed parameters

| Parameter | Value | Rationale |
|---|---|---|
| Reporting grain | Enrolment (student × course) | Grain at which completion occurs |
| Active-learner window | 28 days | Standard MAU window for self-paced learning |
| Lesson dedup | Earliest completion per enrolment+lesson | Learner completed the lesson once |
| Assessment pass rule | Any graded passing attempt | Best outcome wins; mastery demonstrated |
| Ungraded attempts | Excluded from completion | Mid-flight, not yet decided |
| Recommended external rate | Assessment passed (29.7%) | Certificate must be audit-defensible |
| Recommended internal rate | All lessons (44.2%) | Measures actual consumption |