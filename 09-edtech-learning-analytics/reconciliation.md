# Reconciliation Write-Up — The Completion Gap

**Client:** Lumen Lyceum
**Consultant:** Joy Rereloluwa Ogunmodede
**Date:** July 2026
**Dataset:** 12,000 enrolments, 3,792 people, seed 42.

**The question:** Depending on which team you ask, course completion is "45% or 30%."
Marketing quotes one, enterprise procurement audits against another, and they do not
reconcile. The VP of Learning needs one defensible definition and an explanation of the gap.

---

## Executive summary

Both numbers are true — they measure different things. Completion at Lumen Lyceum ranges from
**29.7% to 51.0%** depending on the definition. The two numbers the VP cited are the
all-lessons rate (**44.2%**, Curriculum) and the assessment-pass rate (**29.7%**,
Credentialing) — a **14.5-point gap**. This model computes all four definitions from one
mart and walks the bridge between them, line by line. Critically, the gap runs in *both*
directions: some learners finish lessons but never test, and others pass the test without
finishing every lesson.

---

## The four definitions

| Definition | Owner | Count | Rate | What it captures |
|---|---|---|---|---|
| 80%+ lessons | Curriculum (lenient) | 6,122 | 51.0% | Consumed most of the material |
| All lessons | Curriculum (strict) | 5,300 | 44.2% | Finished every lesson — the "45%" |
| Assessment passed | Credentialing | 3,568 | 29.7% | Demonstrated mastery — the "30%" |
| Platform status | Source system | 3,369 | 28.1% | The overnight job's guess (stale) |

---

## The bridge: walking 44.2% → 29.7%

Every enrolment lands in exactly one category:

| Category | Count | Where it sits in the gap |
|---|---|---|
| Passed the exam | 3,568 | Both teams agree: complete |
| Finished lessons, never sat the exam | 1,378 | Curriculum counts; Credentialing does not |
| Sat the exam and failed | 1,520 | Attended but no mastery; neither counts as passed |
| Genuinely incomplete | 5,534 | Neither team counts |

Plus, running the *other* way:

| Flag | Count | Effect |
|---|---|---|
| Tested out (passed exam without finishing all lessons) | 595 | Credentialing counts; strict-Curriculum does not |

**So the 14.5-point gap is not one population — it is two opposing flows.** The 1,378
lessons-no-exam learners inflate Curriculum's number above Credentialing's; the 595
tested-out learners pull the other way. Netting them explains why the two headline numbers
never reconciled: they were counting different, partially-overlapping groups.

---

## The person-vs-enrolment trap

12,000 enrolments belong to only **3,792 people** (~3.2 enrolments each). Every rate above
is enrolment-grain. If the denominator switches to people ("what % of learners have completed
at least one course?"), the number changes entirely. Any completion figure on a board deck
must state its unit — the model carries both so neither is silently assumed.

---

## The three headline findings

### 1. Completion is a range, not a number
Reporting a single completion rate hides a 21-point spread (29.7%–51.0%). Recommended:
assessment-pass (29.7%) for external/audit use where a certificate must be defensible;
all-lessons (44.2%) for internal engagement reporting. Never one number without its definition.

### 2. The platform status field cannot be trusted
The overnight job reports 28.1% complete — close to the assessment number by coincidence, but
it does not match any event-based definition cleanly. It should not be the source of truth for
any published metric.

### 3. 1,378 learners finished the work but never got credit
That is 11.5% of all enrolments who consumed the full curriculum but never sat the exam. This
is a revenue and retention opportunity — a targeted "you're one exam away from a certificate"
nudge addresses exactly this population.

---

## Data quality issues surfaced (for the client to fix at source)

| Issue | Count | Recommendation |
|---|---|---|
| Duplicate lesson completions (device switch) | 2,275 | Make lesson-event logging idempotent |
| Dropped lesson end-timestamps | 4,694 | Improve player telemetry reliability |
| Stale enrollment_status field | — | Fix or retire the overnight status job |
| Ungraded assessment attempts | 102 | Normal lag — no fix, just exclude from completion |

---

## What I fixed vs what the client must fix

**Fixed in the pipeline:** device-switch lesson dedup, best-attempt assessment logic,
ungraded-attempt exclusion, four-way completion classification, the tested-out and
lessons-no-exam categorisation, timestamp-fallback for missing end times, and the
enrolment-grain-with-person-rollup structure.

**Client must fix at source:** the non-idempotent lesson logging, the player telemetry gaps,
and the stale overnight status job. The warehouse can flag and work around these; only the
source systems can cure them.

---

*Metric definitions for every headline number are maintained separately in
`metric_definitions.md`.*