# Phase 2 — "Run my session and remember it" — Design

_Date: 2026-08-29. Status: draft for review._

**Parent:** `docs/04-roadmap-phases.md` §Phase 2. Builds on Phase 1 (`FitnessCore`
package + `FitnessTracker` app, merged to `main` at `99d2600`).

**Companion specs:**
- Phase 2-chat (the "ask your data" chat interface) — separate spec, written after this ships.
- Phase 3 (rolling re-plan, mid-session AI swap) and Phase 4 (InBody) unchanged.

---

## 1. Goal

Train from the app and build history. Open a scheduled session, get it finalised
for today's energy and time by an AI coach that reads your real logged
performance, run it one exercise at a time (with freedom to jump around), log
every set, and finish with a summary that captures how it felt. Everything is
stored, nothing is thrown away, and the coach's knowledge of you compounds
session over session.

**Done when:** a full gym session can be run start-to-finish from the app; last
session's actual numbers show up as this session's targets; a forced AI-failure
still produces a working rule-engine session; the coach's memory visibly updates
after a session and is fully inspectable.

---

## 2. Scope

**In Phase 2:**
- Session lifecycle + guided-flexible session runner UI.
- The `finalize` AI call (session coach agent) + rule-engine fallback.
- Comprehensive metrics data layer (typed core + extensible observation channel +
  derived rollups + one query API).
- The coach **memory layer** — self-curating, confidence-weighted, user-visible.
- Progress analyst + light recovery advisor agents (run on session write).
- History / progression / PR views.
- "Pick a split style + tweak" starting point for the weekly plan.

**Deferred (explicit):**
- Chat interface → Phase 2-chat (separate later spec).
- Mid-session AI exercise swap with 2–3 alternatives → Phase 3.
- Rolling weekly re-plan / automatic deload week → Phase 3 (Phase 2 *captures* the
  signals; it does not yet re-plan the week).
- Faithful named programs run exactly to spec (5/3/1, PHUL) → Later.
- Apple Health / HRV / sleep import → Later (Phase 2 has a manual daily check-in
  only).
- InBody → Phase 4.

---

## 3. Session lifecycle

States: **Scheduled → Finalizing → Active → Summary → Complete | Partial**

1. **Scheduled** — today's `PlannedSession` exists in the active `WeeklyPlan`
   (Phase 1), untouched.
2. **Finalizing** — user taps "Start". Collects `energyRating`
   (`beat | normal | great`) and `timeAvailableMinutes` (45 / 60 / 90 / custom).
   Runs the `finalize` call (§5). On success → validated, finalised
   `PlannedSession` for today. On failure / offline → rule-engine finalisation
   (§5.4). Never blocks; a backup-coach indicator shows when the rule engine drove.
3. **Active** — the runner (§6). Every `LoggedSet` is persisted on entry
   (crash/quit safe). Each exercise carries its own state:
   `notStarted | inProgress | done`. The user ticks an exercise `done` explicitly;
   logging its last planned set auto-suggests `done` but does not force it.
4. **Summary** — reached by "Finish session". Shows volume vs target, PRs hit,
   per-exercise feel capture, partial reason if applicable, optional overall note,
   one-line coach wrap-up.
5. **Complete** — every exercise `done`. **Partial** — "Finish session" pressed
   with ≥1 exercise not `done` (one confirmation tap, no repeat nagging), OR the
   session was abandoned (app left mid-session, not resumed within 4h → auto-close
   as partial). Everything logged is kept and counts toward weekly volume either
   way.

### 3.1 Feedback capture (at Summary)

- **Per exercise:** `feel` ∈ `easy | right | brutal` + optional one-line note.
  Three taps, skippable.
- **If partial:** "what got in the way?" — chips
  (`ran out of time | too tired | pain/niggle | gym crowded | not feeling it | other`)
  + optional text.
- **Overall:** optional free-text session note.

All feedback is stored on `CompletedSession` / `CompletedEntry` and is a primary
input to (a) the next `finalize` for this session type and (b) the memory-keeper
step (§7.2).

---

## 4. The agent layer

Not separate processes — each agent is an `LLMCallType` with its own system
prompt, tool set, and output schema, over shared context: the
`MetricsRepository` (§8.4) and the memory layer (§7).

| Agent | Job | Trigger | Phase |
|---|---|---|---|
| Planner | the weekly `WeeklyPlan` | week rollover | 1 (exists) |
| **Session coach** | `finalize` — today's session, progression, insights | session Start | **2** |
| **Progress analyst** | stall detection, deload signal, milestones, PR-readiness insights | on `CompletedSession` write | **2** |
| **Recovery advisor** | reads daily check-ins + feel history, emits "back off" signal | on session write / week rollover | **2** (light) |
| Q&A agent | chat over your data | on demand | 2-chat |
| InBody analyst | scan → trend signals | monthly | 4 |

All agent calls flow through the Phase 1c `LLMProvider` / `PlanCoordinator`-style
spine: **build prompt → call → validate against rule-engine guardrail → retry
once with errors → deterministic fallback**. Every call is written to the
`AICallRecord` ledger and shown in the cost chip / Usage screen from Phase 1c.

---

## 5. The `finalize` call (session coach)

### 5.1 Input

- Today's `PlannedSession` (exercises, target sets/reps/loads, `restSeconds`).
- `energyRating`, `timeAvailableMinutes`.
- Last 2–4 `CompletedSession`s covering these exercises: actual reps + loads per
  set, per-exercise `feel`, notes.
- Relevant memory slice (§7.3) — tag-matched to today's exercises/muscles.
- Volume-landmark band (MEV/MAV/MRV) and rep ranges for the muscles trained.
- Catalog slice for owned equipment (ids + names + muscles + rep ranges).

### 5.2 Output (same `PlannedSession` schema + extras)

- Exercises **reordered** and **trimmed** to fit time + energy.
- Per-exercise **target load and sets** finalised for today (the progression
  decision: bump / hold / back off / add set / cut volume).
- Per changed exercise: a short `why` string.
- 0–3 structured **insights**: `{ kind, text, anchor }` where `kind` ∈
  `prReady | milestone | catchUp | caution | encouragement` and `anchor` points
  at an exercise / muscle / the session. UI renders these on cards + as toasts;
  none are a "briefing wall".

### 5.3 Guardrail (rule engine — extends Phase 1 `PlanValidator`)

Applied to the finalised session before the user sees it. Each violated item is
snapped back to the rule-engine value; the rest of the coach's output is kept.

- Per-exercise load change capped: **≤ +10% / ≤ −15%** vs last actual working load.
- Weekly set volume per muscle stays within **MEV…MRV**.
- Rep targets within each exercise's sane range.
- No exercise excluded by equipment or a limitation.
- Session's summed working time (sets × est. time + rest) fits
  `timeAvailableMinutes` within a tolerance.

### 5.4 Fallback (deterministic, fully offline)

No network / call fails / airplane mode at Start → **rule-engine finalisation**:

- Progression rule (from `FitnessCore/RuleEngine`, made real in this phase):
  `easy` + hit target reps → +load (capped) · `right` → repeat or small bump ·
  `brutal` or missed reps → hold or −load. Per-session increase cap enforced.
- Trim to `timeAvailableMinutes` by dropping the lowest-priority accessory first.
- `why` strings are generic; a backup-coach indicator is shown.
- `WeeklyPlan.source` semantics extended: the `CompletedSession` records
  `coachSource ∈ ai | rule`.

### 5.5 Cost

One `finalize` call per session (~2.5k in / ~800 out per `docs/08`). Logged to
`AICallRecord` with `callType = "finalize"`.

---

## 6. Session runner UI

- **Start screen** — session name, exercise count, est. time; energy as 3 large
  buttons; time as chips (45 / 60 / 90 / custom). "Start" → finalize (skeleton
  view ~2–4s) → runner.
- **Focus view** (one exercise) — name, instruction image + cues; set list, each
  row pre-filled with today's target (reps × load), tap to log **actual** with
  +/− steppers for reps and load and a plate-math helper; "done" tick for the
  exercise. A pull-tab reveals the full session list.
- **Session list view** — every exercise with a state dot
  (`notStarted | inProgress | done`), drag to reorder, swipe to "skip" (marks
  `done` with `skipped` flag). "Finish session" is always reachable here.
- **Between sets** — rest timer (§ below) auto-starts; next set row highlighted.
- **Summary** — volume vs target per muscle; PRs hit (each also toasted live the
  moment it happens); per-exercise `feel` (3 taps); partial reason; optional note;
  one-line coach wrap-up. "Save" → persists the `CompletedSession` and fires the
  Progress analyst + Recovery advisor + memory-keeper.

### Rest timer

Auto-starts on set log using that exercise's `restSeconds` (coach-set; heavier →
longer). Circular countdown on the focus view. Haptic + optional sound at zero;
local notification if the app is backgrounded. Tap for +30s / −30s / skip. Never
blocks logging — logging the next set early resets it.

---

## 7. The memory layer

New `FitnessCore` module: **`CoachMemory`**. Sits beside `Metrics`. Distinct from
metrics: **metrics are events and numbers; memory is qualitative knowledge the
coach has earned or been told.**

### 7.1 Record

`CoachMemory`:
- `id`
- `kind` ∈ `preference | constraint | observation | goal | responsePattern`
- `statement` — plain language, e.g. *"reps collapse when sessions run past
  60 min"*, *"left shoulder flares on wide-grip pressing"*.
- `action` — the "so what", e.g. *"cap this session at 45 min; cut the last
  accessory first"*. May be empty for pure `goal`/`preference`.
- `confidence` ∈ `[0,1]`
- `source` ∈ `agent:<name> | user`
- `createdAt`, `lastConfirmedAt`
- `supersededBy: CoachMemory.id?` (retired, not deleted)
- `tags` — `{ exerciseID?, muscle?, equipment?, freeTags: [String] }`
- `outcomeScore` — running signal of whether acting on this memory improved
  subsequent results (§7.4); `nil` until it has been acted on.

Extensible like the observation channel: new `kind`s and `freeTags` need **no
schema migration** (`kind` stored as string; `tags` as a small JSON blob).

### 7.2 Consolidation (memory-keeper step, runs on `CompletedSession` write)

A dedicated call reviews the session's signals and, for each candidate lesson,
does exactly one of:
- **Write** a new `CoachMemory` (low starting `confidence`).
- **Reinforce** an existing near-duplicate: raise `confidence`, update
  `lastConfirmedAt`.
- **Retire** a contradicted memory: set `supersededBy` to the new one; keep the
  trail.

It never stores the same lesson twice. Deterministic guardrail: memory count per
`kind` is capped; lowest-confidence, least-recently-confirmed entries are retired
first when over cap.

### 7.3 Recall (selection step, before every agent call)

Pull the relevant slice by: tag match to the call's subject (today's
exercises/muscles/equipment) → then rank by `confidence × recency` → cap to a
token budget. A compact **profile digest** (distilled from all high-confidence
memories, refreshed weekly or after N new memories) always rides along so every
call starts grounded without loading the full set.

### 7.4 Self-improvement loop

When an agent acts on a memory (recorded on the `AICallRecord` / session), the
**next** session's result updates that memory's `outcomeScore`: reps recovered /
`feel` improved / adherence held → score up; no effect or worse → score down.
`outcomeScore` feeds back into the recall rank, so advice that demonstrably works
surfaces more; advice that didn't fades. Grounded in logged results, not vibes.

### 7.5 User control

A **"What your coach knows about you"** screen: every non-retired `CoachMemory`,
grouped by `kind`, showing `statement`, `action`, a confidence indicator, and
source. The user can **confirm** (jump to high confidence), **edit**, or
**delete**. User-authored or user-confirmed memories are pinned high-confidence
and the coach does not argue with them (mirrors "user instruction overrides
inference"). Adding a memory directly: a free-text "tell the coach…" field.

---

## 8. The data layer

New `FitnessCore` module: **`Metrics`**. Pure, testable, reusable. Three tiers +
one query surface.

### 8.1 Typed core (`@Model`, indexed)

- `CompletedSession` — `date`, `weekday`, `timeOfDay`, `plannedDurationMin`,
  `actualDurationMin`, `energyRating`, `timeAvailableMin`, `outcome ∈ complete |
  partial`, `partialReason?`, `coachSource ∈ ai | rule`, `finalizeRationale?`,
  `insights: [Insight]`, `overallNote?`, link to the source `PlannedSession`.
- `CompletedEntry` — one per exercise: `exerciseID`, `performedOrder`,
  `state ∈ notStarted | inProgress | done`, `skipped: Bool`, `wasSwappedFrom?`
  (always nil in Phase 2), `feel?`, `note?`, `tonnage`, `bestSetE1RM`.
- `LoggedSet` — `targetReps`, `targetLoadKg`, `actualReps`, `actualLoadKg`,
  `startedAt`, `completedAt`, `restBeforeSec`, `rpe?`, flags
  (`isWarmup | isDropSet | toFailure | assisted`).
- `BodyweightEntry` — `date`, `kg`.
- `DailyCheckin` — `date`, `sleepQuality? ∈ 1…5`, `soreness? ∈ 1…5`, `note?`.
  Optional; a 10-second prompt, never required.
- `PersonalRecord` — `type ∈ heaviestWeight | repsAtWeight | estimated1RM`,
  `exerciseID`, `value`, `date`, link to the `CompletedSession`.

### 8.2 Extensible observation channel

`Observation` — `kind: String`, `value: Double`, `unit: String`,
`timestamp: Date`, `context: [String: String]`, optional links to
session/entry/set. New metrics (grip width, bar tempo, gym location, imported
Health data, mood, caffeine) are captured here with **zero migration**.

### 8.3 Derived rollups (computed incrementally on session write, cached `@Model`s)

- `WeeklyMuscleVolume` — `weekStart`, `muscle`, `sets`, `band` snapshot.
- `ExerciseTrendPoint` — `exerciseID`, `date`, `e1RM`, `bestSetLoad`,
  `bestSetReps`, `tonnage`.
- Frequency-per-muscle, adherence %, streak, milestone flags — small cached
  aggregates, recomputed for the affected window only.

### 8.4 Query surface — `MetricsRepository`

One typed Swift API, the single source of truth for "what do my numbers say":
- `lastPerformance(exerciseID:) -> ExercisePerformance?`
- `bestSet(exerciseID:, since:) -> LoggedSet?`
- `e1RMSeries(exerciseID:, range:) -> [ExerciseTrendPoint]`
- `weeklyVolume(muscle:, weeks:) -> [WeeklyMuscleVolume]`
- `prs(exerciseID:?) -> [PersonalRecord]`
- `adherence(weeks:) -> Double`
- `stalls() -> [ExerciseID]`
- `observations(kind:, range:) -> [Observation]`

Consumers: history views (now), the `finalize` input builder (now), the Progress
analyst (now), **Phase 2-chat tools (thin wrappers over this API)**.

### 8.5 Scale

Single user, years of data ≈ low tens of thousands of `LoggedSet`s — trivial for
SwiftData. Rollups keep read paths O(window), not O(history).

---

## 9. History & progression views

- **Per exercise** — e1RM line over time, best set per session, working-weight
  progression, PR markers, "last: 3×8 @ 60kg, felt right".
- **Per muscle / week** — sets logged vs MEV–MAV–MRV band; tonnage trend.
- **Sessions** — calendar/list; adherence %; streaks; partials flagged with
  reason.
- **PR log** — every PR, newest first, tap through to its session.
- All read through `MetricsRepository`; all fully offline.

---

## 10. Pick-a-split starting point

A bundled `ProgramTemplate` catalog (PPL 6-day, Upper/Lower 4, Full-body 3, etc.
— the split templates already exist internally in `FitnessCore/RuleEngine` from
Phase 1). In onboarding / plan settings the user picks a split style and may
tweak days / swap exercises / nudge volume; the Planner then adapts **forward
from those edits** rather than from a blank slate. Faithful named programs run
exactly to spec stay in the Later bucket.

---

## 11. Module / file impact

**`FitnessCore` (new modules):**
- `Metrics` — the §8 types, rollup computation, `MetricsRepository`,
  progression rule (made real), e1RM math, PR detection. Pure. Highest test
  coverage.
- `CoachMemory` — the §7 record, consolidation/recall/decay logic as pure
  functions over injected memory sets (the LLM call is wired in the app layer,
  same as Phase 1c's `PlanCoordinator`).
- `RuleEngine` — progression rule promoted from stub to real; `finalize`
  guardrail validation added alongside the existing `PlanValidator`.

**`FitnessTracker` app:**
- `AI/` — `SessionFinalizeCoordinator` (mirrors `PlanCoordinator`),
  `FinalizePromptBuilder`, `MemoryKeeper` + `ProgressAnalyst` + `RecoveryAdvisor`
  coordinators, new `LLMCallType`s.
- `Models/` — SwiftData `@Model`s for §8.1/§8.3 and `CoachMemory`; container
  schema extended.
- `Features/Session/` — Start, Focus, SessionList, RestTimer, Summary views +
  an `@Observable SessionRunner` store.
- `Features/History/` — the §9 views.
- `Features/Coach/` — the "what your coach knows" screen.
- `Features/Plan/` — pick-a-split UI.

---

## 12. Testing strategy

- `FitnessCore/Metrics` + `CoachMemory` + progression rule + guardrail — pure
  unit tests, exhaustive. This is the safety-critical layer.
- `finalize` / memory / analyst coordinators — `StubLLMProvider`, generate →
  validate → retry → fallback paths, same pattern as Phase 1c.
- SwiftData models — in-memory `ModelContainer` round-trips; rollup
  recomputation correctness.
- Session runner — `@Observable` store logic unit-tested; a small UI smoke for
  the log-a-set → rest-timer → next-set loop.
- No real network anywhere.

---

## 13. Resolved decisions

1. **Daily check-in — IN Phase 2.** A 10-second optional sleep/soreness prompt
   (`DailyCheckin`, §8.1). Cheap to build, feeds the recovery advisor, and fits
   the "store everything" intent. Never required; skippable in one tap.
2. **Memory-keeper is its own LLM call.** A dedicated consolidation step
   (write / reinforce / retire) with a prompt focused only on that job, not a
   side-effect of the Progress analyst. The memory layer is central to the
   product ("a coach that learns like you do"); it gets its own seat. Cost: one
   modest call per completed session, on the `AICallRecord` ledger like the rest.
3. **e1RM = Epley:** `e1RM = load × (1 + reps / 30)`. Used for
   `PersonalRecord.estimated1RM`, `ExerciseTrendPoint.e1RM`, and the analyst's
   PR-readiness insight. Single formula everywhere.
4. **Pick-a-split — IN Phase 2.** It is the "set/get pre-made workouts +
   tweakability" the product calls for and belongs with the plan/session
   experience, not deferred.

## 14. Sub-plan breakdown

Phase 2 is built as four sequential sub-plans (mirrors Phase 1's 1a/1b/1c), each
independently reviewable and each leaving the app working:

- **2a — `FitnessCore` foundation.** New `Metrics` module (§8 types as pure
  value models + rollup math + `MetricsRepository` + Epley e1RM + PR detection),
  new `CoachMemory` module (§7 record + consolidation/recall/decay as pure
  functions over injected sets), `RuleEngine` progression rule promoted stub →
  real + the `finalize` guardrail validator. No app changes. Pure unit tests.
- **2b — persistence + session runner.** SwiftData `@Model`s for §8.1/§8.3 and
  `CoachMemory`; container schema migration; `@Observable SessionRunner`; Start /
  Focus / SessionList / RestTimer / Summary views; feedback capture. Rule-engine
  finalisation only (no AI yet) so the runner is fully exercised offline first.
- **2c — the coach agents.** `SessionFinalizeCoordinator` +
  `FinalizePromptBuilder`; `MemoryKeeper`, `ProgressAnalyst`, `RecoveryAdvisor`
  coordinators; new `LLMCallType`s; wire into the runner's Start and the
  post-session write. Same generate → validate → retry → fallback spine as
  Phase 1c.
- **2d — history + pick-a-split.** The §9 views over `MetricsRepository`; the
  "what your coach knows" screen (§7.5); the §10 pick-a-split UI.

The chat "ask your data" interface is a **separate later spec** (referred to
elsewhere as Phase 2b — renamed **Phase 2-chat** here to avoid the sub-plan
letter clash) and is out of scope for all four sub-plans above.
