# Orchestration DAG Design — Lumen Lyceum Learning Analytics Pipeline

**Tool:** Dagster (recommended) or Airflow
**Schedule:** Daily at 05:00 UTC
**Re-run strategy:** Full refresh (idempotent)

---

## DAG overview

```
source_freshness_check
        │
        ▼
   ┌─ stg_students
   ├─ stg_courses
   ├─ stg_lessons
   └─ stg_assessments
        │
        ▼
   int_enrollment_progress
        │
        ▼
   mart_enrollment_completion
        │
        ▼
   mart_completion_summary
        │
        ▼
   dbt_test (all 23 tests)
        │
        ▼
   notify_on_completion
```

---

## Schedule and rationale

| Parameter | Value | Rationale |
|---|---|---|
| Schedule | Daily, 05:00 UTC | Runs after overnight lesson + assessment event exports land. Completion flags refresh each morning. |
| Run type | Full refresh | Staging are views; marts are small (12k enrolment rows, 1 summary row). Lesson table is ~80k rows but the dedup + aggregation is cheap. |
| Timeout | 30 minutes | Full build runs in ~32 seconds. Generous margin. |
| Retry policy | 2 retries, 5-min backoff | Transient Snowflake drops. |

---

## Source freshness checks

Run `dbt source freshness` first.

| Source | loaded_at_field | Warn after | Error after | Action on error |
|---|---|---|---|---|
| raw_lessons | started_at | 30 hours | 48 hours | Block — stale lessons break the lessons-completion signal |
| raw_assessments | submitted_at | 30 hours | 48 hours | Block — stale assessments break the pass signal |
| raw_students | last_active_at | 48 hours | 72 hours | Warn — enrolment records change slowly |
| raw_courses | — | n/a | n/a | No check — static catalogue |

**Why lessons and assessments gate the pipeline:** they drive the completion definitions.
Stale lesson data understates lessons-based completion; stale assessments understate the
pass rate. Students and courses are slow-changing and non-blocking.

---

## Dependency structure

**Layer 1 — Freshness:** lessons/assessments errors block; students warn.

**Layer 2 — Staging (parallel):** all 4 staging views. Near-zero runtime.

**Layer 3 — Intermediate:** int_enrollment_progress — rolls up deduped lessons + best
assessment outcome per enrolment. Heaviest step (scans ~80k lesson rows).

**Layer 4 — Marts (sequential):** mart_enrollment_completion (per-enrolment flags) →
mart_completion_summary (aggregate reconciliation).

**Layer 5 — Testing:** all 23 tests. Business-rule failures at error severity block.

**Layer 6 — Notification:** success → Slack #learning-analytics with the four completion
rates + the gap; failure → PagerDuty + Slack.

---

## Failure modes and responses

| Failure | Detection | Impact | Response |
|---|---|---|---|
| Snowflake unreachable | Timeout at freshness | No update | Retry 2x, then alert |
| Lessons stale | Freshness error | Lessons-completion understated | Block, alert |
| Assessments stale | Freshness error | Pass rate understated | Block, alert |
| Staging view fails | dbt build error | Downstream skips | Alert — likely source schema change |
| Mart build fails | dbt build error | Stale completion snapshot served | Alert; last good table remains |
| Business-rule test fails | dbt test error | Logic error in flags | Block, alert, investigate |
| all_lessons > 80pct_lessons | Business-rule test | Set-logic broken | CRITICAL — strict count exceeds lenient, math is wrong |
| total_people > total_enrollments | Business-rule test | Grain error | CRITICAL — person/enrolment relationship inverted |

---

## Idempotency guarantees

- **Views** (staging): always reflect current source.
- **Tables** (marts): CREATE OR REPLACE each run.
- **Deterministic:** same raw data = same completion flags.
- **Re-run safe:** re-running produces identical output.

---

## Recommended monitoring

- Four completion rates tracked over time — divergence trend between lessons and assessment
- The lessons-no-exam count (1,378 today) — a spike is a retention opportunity signal
- Duplicate lesson-event rate — a rise signals a logging regression
- Lesson freshness — the most important input to lessons-based completion

---

## Why Dagster over Airflow

Dagster's asset model maps 1:1 to dbt's ref() graph via dagster-dbt, so the orchestrator's
DAG mirrors the dbt lineage automatically. Its native freshness policies suit a daily-loaded
platform feed. Airflow works but requires manual sensor wiring for freshness and manual
dependency wiring.