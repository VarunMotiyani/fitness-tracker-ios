# Phase 3e — Notes + scheduling — Implementation Plan

> SDD ledger at `.superpowers/sdd/2026-09-03-phase-3e-notes-scheduling/`. Steps use `- [ ]`.

**Goal:** Exercise notes (three distinct kinds) and a session note; a weekly plan grid with per‑day reschedule overrides; "what's next" when today is a rest day; a configurable week start (Mon/Sun) threaded through streak, heatmap and calendar.

**Reference:** `~/Documents/person/opengym/frontend/src/lib/history.js` (`pinnedNoteFor`, `exNoteFor`, `NOTE_MAX`, `effectiveRoutineId`, `nextTrainingDay`, `streakWeeks`), `lib/finish-workout.js` (`note`, `notePin`, session note), `views/Plan.jsx`, `views/Home.jsx`, `components/Heatmap.jsx`.

## Global Constraints

Phase 3 spec. Mostly independent of 3a–3d. `FitnessCore` helpers pure. Data model stays openGym‑JSON compatible: notes on entry (`note`, `notePin`), session (`note`), a per‑exercise standing‑note map, `dayPlan` map, `weekStart` setting.

## File Structure

- Create `FitnessCore/Sources/RuleEngine/Scheduling.swift` — `effectiveRoutine(state:date:)`, `nextTrainingDay(state:from:)`, week‑key helpers parameterised by `weekStart`.
- Create `FitnessCore/Sources/Metrics/WeekKey.swift` — `weekStart`‑aware ISO/US week keys, used by `StreakCalculator` + heatmap.
- Modify `FitnessCore/Sources/Metrics/StreakCalculator.swift` — take `weekStart`.
- Modify `FitnessCore/Sources/Metrics/MetricSnapshots.swift` + app `SessionModels.swift` — entry `note`/`notePin`, session `overallNote` (already present), a standing‑note store.
- Modify `FitnessTracker/FitnessTracker/Models/UserProfile.swift` or `@AppStorage` — `gym_week_start` (exists in `SettingsView`), `dayPlan` (a small `@Model` or a JSON field on `StoredPlan`).
- Views: `PlanView.swift` (weekly grid + reschedule), `HomeView.swift` (`nextTrainingDay`), `DayOverrideSheet.swift` (exists — wire it), `SessionFocusView.swift` / `SessionSummaryView.swift` (note fields), `ExerciseDetailSheet.swift` (standing note).
- Tests: `SchedulingTests.swift`, `WeekKeyTests.swift`, extend `StreakCalculatorTests.swift`.

---

## Task 1: `WeekKey` + `StreakCalculator` take `weekStart`

**Files:** create `WeekKey.swift`; modify `StreakCalculator.swift`; extend `StreakCalculatorTests.swift`.

```swift
public enum WeekStart: String, Sendable, Codable { case monday, sunday }
public enum WeekKey {
    /// The start-of-week date for `date` given `weekStart`.
    public static func startOfWeek(_ date: Date, weekStart: WeekStart, calendar: Calendar = .isoUTC) -> Date
    /// A stable "YYYY-Wnn" key for grouping/streaks.
    public static func key(_ date: Date, weekStart: WeekStart, calendar: Calendar = .isoUTC) -> String
}
```
`StreakCalculator.computeSummary(..., weekStart: WeekStart)` uses `WeekKey`. **`workoutsThisWeek`, `currentStreakWeeks`, `totalWorkouts` become the single source** — Home and Stats both call this; delete Home's own streak math.

- [ ] Tests: a Sunday session and the following Saturday session are the same week under `.sunday`, different weeks under `.monday`; streak counts consecutive week keys back from now under each setting; a known fixture's `currentStreakWeeks` matches whatever the app shows in one place only.
- [ ] Implement; green; commit `WeekKey + weekStart-aware StreakCalculator (single source)`.

## Task 2: `Scheduling` — effective routine + next training day

**Files:** create `Scheduling.swift`; test `SchedulingTests.swift`.

```swift
public enum Scheduling {
    /// The routine that applies on `date`: a `dayPlan[iso]` override ("rest" → nil, or a
    /// routine id) wins; otherwise the weekday's assigned routine from `week`.
    public static func effectiveRoutineID(state: SessionState, date: Date) -> String?
    /// The next date on/after `from` that has a non-rest effective routine (scan a bounded
    /// window, e.g. 14 days). nil if nothing is scheduled.
    public static func nextTrainingDay(state: SessionState, from: Date) -> (date: Date, routineID: String)?
}
```
`SessionState` carries `week: [Int: String]` (weekday→routineId), `dayPlan: [String: String]` (isoDate → routineId | "rest"), `routines: [Routine]`.

- [ ] Tests: no override → weekday routine; `dayPlan["2026-09-04"] = "rest"` → nil that day; `dayPlan[...] = <other routine id>` → that routine; `nextTrainingDay` skips rest days and today if today is rest; returns nil when `week` is empty and no overrides.
- [ ] Implement; green; commit `Add Scheduling: effectiveRoutineID + nextTrainingDay with day overrides`.

## Task 3: Notes — model + finish flow

**Files:** `MetricSnapshots.swift`, `SessionModels.swift`, `ModelSnapshotMapping.swift`, `SessionFinalizer.swift`/`SessionRunner.swift`; tests.

- `CompletedEntrySnapshot.note: String?` (exists), add `notePin: Bool` (default false — "show this again next time").
- `CompletedSessionSnapshot.overallNote` (exists) — surface it in the finish flow.
- A standing per‑exercise note store: `exNotes: [String: String]` on the profile/state (openGym `exNoteFor`); `pinnedNoteFor(exerciseID:sessions:)` returns the most recent entry `note` where `notePin == true`, with its date.
- `NOTE_MAX = 500` — clamp on write.
- Finish flow persists: entry `note` + `notePin`, session `overallNote`, all trimmed, written only when non‑empty (an untouched entry stays byte‑for‑byte its old shape).

```swift
public enum Notes {
    public static let maxLength = 500
    public static func standing(exerciseID: String, exNotes: [String: String]) -> String?
    public static func pinned(exerciseID: String, sessions: [CompletedSessionSnapshot]) -> (note: String, date: Date)?
    public static func clamp(_ s: String) -> String   // trim + cap at maxLength
}
```

- [ ] Tests: `pinned` returns the newest pinned entry note + date, nil when none pinned; `clamp` trims and caps; a session finished with no notes produces entries with no `note`/`notePin` keys.
- [ ] Implement; green; commit `Notes: entry note + pin, session note, standing note, NOTE_MAX`.

## Task 4: Notes — UI (three kinds, never interchangeable)

**Files:** `SessionFocusView.swift`, `SessionSummaryView.swift`, `ExerciseDetailSheet.swift`, new `ExerciseNoteSheet.swift`, `SessionNoteSheet.swift`.

For one exercise, up to three lines, each its own icon:
1. **plan instruction** — the routine item's `coachNote` (read‑only here).
2. **standing note** — `Notes.standing(...)` (info icon), edited on the exercise detail screen.
3. **pinned note** — `Notes.pinned(...)` (highlighted, "From {date}: …"), only while the exercise still has work left.
4. today's note — edited via a button in the exercise header, shown last, with a "keep showing this" toggle → `notePin`.

Session note: a button by the finish action ("Add / Edit session note").

- [ ] Build + UI smoke: add an entry note, pin it, finish, start the same routine → the pinned note shows on that exercise.
- [ ] Commit `Notes UI: plan / standing / pinned / today, plus session note`.

## Task 5: Weekly plan grid + per‑day reschedule

**Files:** `PlanView.swift`, `DayOverrideSheet.swift`, `HomeView.swift`, a `dayPlan` store.

- `PlanView`: a Mon–Sun (or Sun–Sat per `weekStart`) grid, each weekday showing its assigned routine (or "Rest"), tappable to assign/clear via a routine picker; below it, the routine breakdown cards (already there).
- `DayOverrideSheet`: for a specific date — "train {routine}", "rest", or "clear override" — writing `dayPlan[iso]`.
- `HomeView`: the week strip's "TODAY" card uses `Scheduling.effectiveRoutineID(state:today)`; when today is rest, show `Scheduling.nextTrainingDay(...)` ("Next: Push Day, Fri").
- The calendar day sheet gets an "override this day" action.

- [ ] Build + UI smoke: set Wednesday to rest via the grid → Home shows the next training day; override tomorrow to a different routine → Home's card follows.
- [ ] Commit `Plan grid + per-day reschedule overrides; Home uses effective routine + next day`.

## Task 6: Suite sweep

- [ ] `cd FitnessCore && swift test` + `xcodebuild test …` green.
- [ ] Commit `Phase 3e: suites green`.

## Self‑review

Coverage: single‑source streak + weekStart ✅(T1), day overrides + next day ✅(T2/T5), 3 note kinds + session note + pin + NOTE_MAX ✅(T3/T4), plan grid ✅(T5). Types: `WeekStart` (T1) used by `Scheduling`? no — `Scheduling` uses dates; `WeekKey` used by `StreakCalculator` + 3f heatmap.
