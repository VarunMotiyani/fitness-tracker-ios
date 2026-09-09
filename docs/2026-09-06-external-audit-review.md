# Review of the external PulseAI audit (2026-09-06)

Every finding below was checked against the working tree at `e080aa8`. Verdicts:
**CONFIRMED** (real, correctly described) · **CONFIRMED-BUT-OVERSTATED** (real bug, wrong
severity/impact framing) · **DEBATABLE** (real behaviour, but "bug" is a product call) ·
**FIX-IS-WRONG** (bug real, the audit's proposed fix is naive/incorrect).

---

## P0

### 1.1 Finalize guardrails are a no-op — **CONFIRMED** (this is the real one)
`SessionFinalizeCoordinator.finalize` (working tree ~L77-86) calls `guardrail.check(...)` with
`experience: .intermediate`, `excludedExerciseIDs: []`, `excludedMuscles: []`,
`availableEquipment: Set(Equipment.allCases)`, `lastPerformances: [:]` — all hardcoded.
`FinalizeGuardrail.check` (`FitnessCore/.../FinalizeGuardrail.swift`):
- L65-68 gate the exclusion/equipment violations on those (empty/all) sets → never fire.
- **L79 `guard let performance = lastPerformances[item.exerciseID]` — with `[:]` this always
  fails, so the load-jump / load-drop cap (`maxIncreaseFraction: 0.10`) is skipped for every
  item.** The AI can propose any load and `report.violations` is empty.
- L133 `VolumeLandmarks.band(for: muscle, experience:)` uses the hardcoded `.intermediate`.

The retry loop that feeds violations back to the model is therefore dead weight in practice.
**Correct fix:** thread real context — `profile.experienceLevel`, `profile.excludedExerciseIDs`,
`profile.excludedMuscleGroups`, the athlete's active `EquipmentProfile` → `Set<Equipment>`, and
`repository.lastPerformances(for: planned.items.map(\.exerciseID))` (the `SwiftDataMetricsRepository`
already computes per-exercise history for the rule-engine path — reuse it). `SessionFinalizeCoordinator`
already holds `context` + `catalog`; it needs the `profile` and the repo handle passed in
(`SessionContainerView` builds both right before constructing the coordinator).

### 1.2 SigV4 breaks on Bedrock model IDs containing `:` — **CONFIRMED**
`AWSSigV4Signer.swift:50` — `canonicalURI = request.url?.path`. `URL.path` percent-*decodes* and
leaves `:` literal. Bedrock's invoke path is `/model/{modelId}/invoke`; cross-region IDs like
`us.anthropic.claude-3-5-sonnet-20241022-v2:0` put a `:` in a path segment, which AWS canonicalises
as `%3A` → `SignatureDoesNotMatch` (403). `AWSSigV4SignerTests` missed it because the fixture model
id has no colon.
**Correct fix:** build the canonical URI by percent-encoding each path segment with an
RFC-3986-unreserved allowed set (`A-Za-z0-9-._~` plus `/` between segments), NOT
`.urlPathAllowed` (which permits `:`). Add a test with `.../model/x.y-v2:0/invoke`.

### 1.3 "Leave Workout" resumption trap — **CONFIRMED-BUT-OVERSTATED**
Real parts:
- `SessionFocusView` L179-186 — "Leave Workout" → `dismiss()`; copy says "You can resume this
  session anytime."
- `dismiss()` clears `activePlannedSession` (it backs `.fullScreenCover(item:)`), so
  `RootView`'s `isWorkoutActive = activePlannedSession != nil` goes false → FAB shows "Start", not
  a resume affordance.
- `RootView` `onStartPressed` (L108-110) always launches `plan.sessions.sorted{ $0.order }.first`.
- `SessionContainerView.task` (L38-46) closes any `finishedAt == nil` row **for the session slot
  being entered** via `closeSessionAsPartial`.

Overstated / wrong:
- **Not "data loss."** `closeSessionAsPartial` promotes logged sets to volume/PR credit (per its
  own doc comment) — the sets are kept, the session is just marked partial.
- **Not unconditional abandonment.** The orphan-close is scoped to `plannedSessionID == <entered
  slot>`. Leaving Leg Day and tapping the FAB (which opens the order-0 session, say Push Day)
  leaves the Leg Day row open and untouched — it just has no UI path back to it. It only gets
  closed-as-partial if you re-enter *that specific* session (FAB when it is order-0, or its card
  in Plan/Home).

So the real bug is **(a)** the dialog copy lies — there is no resume path, and **(b)** the runner
never re-attaches to an open session, it always closes+restarts.
**Correct fix:** persist the active session's `plannedSessionID` (AppStorage) on start / clear on
finish; `RootView` shows "Resume" when it's set and routes the FAB to that session;
`SessionContainerView` re-attaches the `SessionRunner` to the existing open `CompletedSessionModel`
instead of closing it. If a full resume is out of scope now, at minimum change the dialog copy to
the truth ("Your logged sets are saved" — drop "resume anytime").

---

## P1

### 2.1 `Calendar.isoUTC` in local-facing date math — **CONFIRMED for specific sites, FIX-IS-WRONG as stated**
Real, per site:
- `SessionRunner` (~L104-106): `weekdayRaw` / `timeOfDayMinutes` computed with `Calendar.isoUTC`
  from a real instant → a 21:00 local workout in a negative-offset zone persists as the next
  day, ~04:00. These columns are meant to capture *when the athlete trains* → wrong for any
  non-UTC user. **This one should be `Calendar.current`.**
- `HomeView` "completed today" / week-strip highlight, `StatsView` day grouping: `isDateInToday`
  and weekday-of-week math on `Calendar.isoUTC` misfire in the evening for negative offsets.
  **These display helpers should be local.**

Wrong as a blanket instruction: "replace `Calendar.isoUTC` with `Calendar.current` across
HomeView, StatsView, SessionRunner." `Calendar.isoUTC` is deliberate for **week bucketing** in
`StreakCalculator`, `RecoveryModel`, `MuscleBalanceModel`, and the proactive weekly/day keys —
those need a stable, timezone-independent bucket so engine math is deterministic and the FitnessCore
tests are reproducible. Swapping those would introduce off-by-one-week nondeterminism and break
tests. **Correct fix:** targeted — local calendar for (i) the two `SessionRunner` persisted
fields, (ii) "is this session today" checks, (iii) the week-strip weekday circles and Stats day
grouping *presentation*. Leave `isoUTC` for cross-session week-interval bucketing. A short
`Calendar` extension doc-comment stating which is which would stop this recurring.

### 2.2 Bodyweight lifts excluded from 1RM / PR — **CONFIRMED, FIX-IS-WRONG**
`Estimated1RM.bestSet` L45 `... && s.actualLoadKg > 0` drops every bodyweight set (they store
`actualLoadKg == 0`). `series`/`best`/PR detection all go dark for pull-ups, dips, etc.
The audit's `actualLoadKg >= 0` is naive: Epley/Brzycki on `load = 0` return `0` — still no
estimate, PRs still never fire. **Correct fix:** for a bodyweight-category exercise, the effective
load is `bodyweight (+ any added load)`. That needs the athlete's bodyweight *at the time of the
set* (nearest `BodyweightEntryModel`, or `profile.weightKg` fallback). This is a small design
task, not a one-line filter change — flag it as such.

### 2.3 No PR detection on import/backfill; orphaned PRs on delete — **CONFIRMED**
- `HistoryIngestionService` (imports) and `HistoryListView.createBackfilledSession` insert +
  `context.save()` with no `PRDetector.newPRs(...)` call.
- `HistoryListView` L65 `context.delete(match)` — `PersonalRecordModel` rows keyed by `session.id`
  are not cascade-deleted (no SwiftData `@Relationship(deleteRule:)` between them).
**Correct fix:** run `PRDetector.newPRs` over each inserted session in both paths (dedupe against
existing `PersonalRecordModel`); on delete, fetch+delete `PersonalRecordModel` where
`sessionID == match.id` in the same transaction (or model the relationship with `.cascade`).
Bulk imports should compute PRs in chronological order so "first time at this weight" is correct.

### 2.4 Loose fuzzy exercise matching on import — **CONFIRMED**
`HistoryIngestionService` ~L67 `catalog.all.first { $0.name.localizedCaseInsensitiveContains(entry.exerciseName) }`
— returns whatever partial-substring match is first in `catalog.all`. "Bench Press" can bind to
"Incline Barbell Bench Press."
**Correct fix:** exact case-insensitive name match first; then a normalized match (strip
punctuation/whitespace); then `contains` only as a last resort, and prefer the *shortest*
candidate name among `contains` hits (closest to the query). Unmatched → keep the
`sanitizeID(name)` synthetic id as today.

### 2.5 Hardcoded 1-hour Hevy durations — **CONFIRMED (minor)**
`HevyAPIClient` ~L112 `durationSeconds: 3600`. Hevy's workout payload carries `start_time` /
`end_time`. Impact is limited to duration stats on imported sessions.
**Correct fix:** parse both timestamps, `durationSeconds = max(0, end - start)`; fall back to
`3600` only if either is missing.

---

## P2

### 3.1 Full-DB JSON export on every AI call — **CONFIRMED**
`SessionFinalizeCoordinator.finalize` L50, `MemoryKeeperCoordinator`, `AskCoachCoordinator` all
build `HistoryExportManager.exportFullJSONData(context:catalog:)` eagerly and hand the `Data` to
`QueryTrainingDataTool(exportJSON:)` — even when the model never calls that tool. Synchronous,
`@MainActor`, whole-DB → nested dicts → `JSONSerialization`. Noticeable on 500+ sessions.
**Correct fix:** make the tool hold a `@Sendable () -> Data` (or an `async` producer) and
memoise on first call. Only pay the cost when `query_training_data` actually fires. Consider
capping/paginating the export too.

### 3.2 Phantom re-seed blocks empty state — **CONFIRMED**
`HomeView.seedInitialDataIfNeeded` (and the LogWeightSheet equivalent) do `if
bodyweightEntries.isEmpty { insert 7 demo rows }`. Delete-all → reopen → demo data returns.
**Correct fix:** a one-shot `UserDefaults` flag (`didSeedDemoBodyweight`) set after the first
seed; never re-seed once set. Or gate seeding on the same "first run / no profile" condition the
rest of the demo seeding uses in `RootView`.

### 3.3 Rest timer freezes when backgrounded — **CONFIRMED**
`RestTimerView.tick()` does `remaining -= 1` on a `Timer.scheduledTimer`; iOS suspends it on
lock/background, and no local notification is scheduled, so a pocketed phone gets no chime.
**Correct fix:** store `targetEndDate = Date() + remaining` on start; on `tick` and on
`scenePhase → .active`, recompute `remaining = max(0, targetEndDate - Date())`; schedule a
`UNTimeIntervalNotificationTrigger` for `remaining` so the alert fires while backgrounded (cancel
it on skip/foreground-complete). Keep `tick()` unit-testable by injecting the clock.

### 3.4 Center FAB always starts the order-0 session — **DEBATABLE**
`RootView` `onStartPressed` L108-110 → `plan.sessions.sorted { $0.order }.first`. If the plan has
day assignments (there is a `dayToRoutine` map in `HomeView`), the FAB ignoring "what's scheduled
today" is inconsistent with the rest of the UI. Whether "Start" means *today's* session or *next
in the split* is a product decision — but it should match the Home "today" card, which it
currently doesn't.
**If treated as a bug:** resolve the same session the Home "today" card resolves and launch that;
fall back to order-0 only when today is a rest day.

### 3.5 PlateMath reports the requested total, not the achievable one — **CONFIRMED (low)**
`PlateMath` greedy loop (~L102-108) stops when no plate fits the remainder; the result still
returns `totalWeight: <requested>` and `perSideWeight: <requested/2>`, so the UI shows "62 kg,
21 kg/side [20]" when only 60 kg is loadable.
**Correct fix:** return the achieved figures — `loadedTotal = barWeight + 2 * sum(plates)`,
`perSideLoaded = sum(plates)`, plus a `remainderPerSide` / `isExact` flag the UI can surface
("closest: 60 kg — 1 kg/side short").

---

## Findings framing / scoring

The layer scores (5/10 etc.) and phrases like "systemic timezone corruption" and "no-op AI
safety guardrails" are editorial. The underlying 1.1, 1.2, 2.3, 2.4, 3.1 findings stand on their
own evidence; 1.3 and 2.1 are real but narrower than written; 2.2's fix is wrong; 3.4 is a
product call. Nothing in the audit is fabricated — every file/line reference resolved.

## Suggested order (if acting on it)

1. **1.1** (safety) + **3.1** (same file, cheap) — one focused change to `SessionFinalizeCoordinator`.
2. **1.2** (Bedrock connectivity) — isolated, `AWSSigV4Signer` + test.
3. **2.3** (PR on import/backfill + cascade delete) — data integrity, self-contained.
4. **2.4** (exact-match-first) — small, same file as 2.3-import.
5. **2.1** targeted (SessionRunner fields + today/week-strip display) — needs care around the
   `isoUTC` bucketing boundary; expect FitnessCore test review.
6. **3.3** (rest timer wall-clock + notification), **3.2** (seed flag), **2.5** (Hevy duration),
   **3.5** (plate math achieved) — independent, low-risk.
7. **2.2** (bodyweight-as-load 1RM) and **3.4** (FAB target) — need a product decision first.
