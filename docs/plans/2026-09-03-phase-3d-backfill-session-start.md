# Phase 3d — Backfill + shared session start — Implementation Plan

> SDD ledger at `.superpowers/sdd/2026-09-03-phase-3d-backfill-session-start/`. Steps use `- [ ]`.

**Goal:** One code path builds a session's exercise entries whether it's a live start or logging a past workout, so a prescription‑rule change can't drift the two. Add "log a past workout" (backfill) — the same runner screen pointed at another date, no rest timers, filed into history in date order.

**Reference:** `~/Documents/person/opengym/frontend/src/lib/session-start.js` (`buildSessionEntries`), `lib/backfill.js`, `views/Workout.jsx` (the `A.backfill` branch), `lib/history.js` (`buildSets`, `applyIntensifierPlan`).

## Global Constraints

Phase 3 spec. Depends on **3a** (prescription) and **3c** (intensifier plan on the set list). `FitnessCore` helpers pure; runner/UI `@MainActor`. Data model stays openGym‑JSON compatible.

## File Structure

- Create `FitnessCore/Sources/RuleEngine/SessionEntryBuilder.swift` — `buildEntries(state:routine:mode:)`.
- Create `FitnessCore/Sources/Metrics/BackfillOps.swift` — date math + chronological insert + replace.
- Modify `FitnessTracker/FitnessTracker/Session/SessionRunner.swift` — build via `SessionEntryBuilder`; a `backfill: BackfillContext?` field; suppress timers; commit via `BackfillOps`.
- Modify `FitnessTracker/FitnessTracker/Features/Session/SessionStartView.swift` + `SessionFocusView.swift` — a "log past workout" entry point, a date/time picker, a banner, no rest UI.
- Create `FitnessTracker/FitnessTracker/Features/History/BackfillEntryView.swift` — date, duration, optional "replaces this session" picker.
- Tests: `SessionEntryBuilderTests.swift`, `BackfillOpsTests.swift`, extend `SessionRunnerTests.swift`.

---

## Task 1: `SessionEntryBuilder`

**Files:** create `SessionEntryBuilder.swift`; test `SessionEntryBuilderTests.swift`.

```swift
public enum SessionEntryBuilder {
    public struct BuiltEntry: Sendable, Equatable {
        public let exerciseID: String
        public let supersetID: String?
        public let target: PrescriptionTarget
        public let prescription: Prescription     // kept so the runner can explain the numbers
        public let sets: [SetRow]
    }
    /// For each routine item: run `ProgressionRule.next` (unless `excludeFromProgression`),
    /// build the base set list from history (`buildSets`), apply the prescription to unlogged
    /// rows, then apply the intensifier plan (drop-set / rest-pause template rows) and
    /// re-ramp warm-ups. `excludeFromProgression` → prescription `.off`, sets from the plan
    /// target verbatim.
    public static func build(state: SessionState, routine: Routine,
                             excludeFromProgression: Bool) -> [BuiltEntry]
}
```
`buildSets(state:cfg:)` — the base row list: for each planned set, seed from the same *position* in the last session's entry (fall back to its final set when the plan grew), per mode; the remembered working weight (`exWeights[id]`) overrides for reps mode. Put `buildSets` in this file (or a sibling `SetSeeding.swift`) — it's pure.

- [ ] Tests: routine with 2 items → 2 `BuiltEntry`; item with history → sets seeded from last time then prescription applied to unlogged rows; `excludeFromProgression` → prescription `.off`, sets == plan target; a bodyweight item under a rep‑ceiling prescription grows its set count (from 3a Task 4); warm‑up rows re‑ramped toward the work weight (from 3a Task 6).
- [ ] Implement; green; commit `Add SessionEntryBuilder: one path for live start + backfill`.

## Task 2: `SessionRunner` builds via `SessionEntryBuilder`

**Files:** `SessionRunner.swift`; extend `SessionRunnerTests.swift`.

- Replace the current inline entry construction in `start(...)` with `SessionEntryBuilder.build(...)`.
- Assert the live‑start behaviour is unchanged (existing runner tests stay green; adjust only where the new seeding is strictly better — note each in the ledger).

- [ ] Tests: existing `SessionRunnerTests` green; a start after a logged session pre‑fills weights from last time.
- [ ] Commit `SessionRunner: build entries through SessionEntryBuilder`.

## Task 3: `BackfillOps`

**Files:** create `BackfillOps.swift`; test `BackfillOpsTests.swift`.

```swift
public enum BackfillOps {
    /// Epoch for `date` at wall-clock `time` (default 18:00), local zone — so a logged
    /// session's `date` and `startedAt` agree the way a live one's do.
    public static func startInstant(date: DateComponents, time: (h: Int, m: Int) = (18, 0)) -> Date
    /// end = start + max(1, durationMin) * 60.
    public static func endInstant(start: Date, durationMin: Int) -> Date
    /// Insert `session` into a chronological [CompletedSessionSnapshot] by (date, startedAt);
    /// a past session goes where its instant puts it, not at the end.
    public static func insertChronological(_ sessions: [CompletedSessionSnapshot], _ session: CompletedSessionSnapshot) -> [CompletedSessionSnapshot]
    /// Drop `replaceID` (if any), then insert chronologically.
    public static func commit(_ sessions: [CompletedSessionSnapshot], _ session: CompletedSessionSnapshot, replaceID: UUID?) -> [CompletedSessionSnapshot]
}
```

- [ ] Tests: a session dated 3 days ago inserts before today's; `commit` with `replaceID` removes the old one; two sessions same instant keep insertion order; `endInstant(start, 0)` == `start + 60s`.
- [ ] Implement; green; commit `Add BackfillOps: chronological insert + replace`.

## Task 4: Backfill mode in the runner + UI

**Files:** `SessionRunner.swift`, `SessionStartView.swift`, `SessionFocusView.swift`, `BackfillEntryView.swift`; extend `SessionRunnerTests`.

- `BackfillContext { date: Date, durationMin: Int, replaceID: UUID? }`. When set:
  - `SessionRunner.start` uses `SessionEntryBuilder` as normal, stamps `startedAt = BackfillOps.startInstant(...)`, `finishedAt = BackfillOps.endInstant(...)`.
  - `WorkoutTimers` is not started; the focus view shows a "Logging a past workout — no rest timers" banner and hides rest UI.
  - `finish()` commits through `BackfillOps.commit(...)` instead of appending, then runs PR / 1RM detection on the new history.
- `BackfillEntryView`: pick a routine (or freestyle), a date, a duration, and optionally "replaces the session on that day"; then push into the runner.
- Entry point: a "＋ Log past workout" button on `HistoryListView` and on the calendar day sheet.

- [ ] Tests: backfill a session dated last week → it lands in `workouts` in date order, `startedAt`/`finishedAt` on that day, no timer started; `replaceID` replaces; PR detection sees the correct prior history (not the whole list including later sessions).
- [ ] Commit `Backfill: log a past workout through the runner, filed chronologically`.

## Task 5: Suite sweep

- [ ] `cd FitnessCore && swift test` + `xcodebuild test …` green.
- [ ] Commit `Phase 3d: suites green`.

## Self‑review

Coverage: unified builder ✅(T1/T2), backfill date math + chronological + replace ✅(T3), backfill runner + UI ✅(T4). Types: `BuiltEntry` (T1) consumed by `SessionRunner` (T2); `BackfillContext` (T4) uses `BackfillOps` (T3).
