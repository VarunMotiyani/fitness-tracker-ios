# Phase 3c — Session runner: supersets, rest rules, intensifiers — Implementation Plan

> SDD ledger at `.superpowers/sdd/2026-09-03-phase-3c-session-runner/`. Steps use `- [ ]`.

**Goal:** The live workout runner behaves like openGym's: rest fires after every completed set (including an exercise's last), unchecking/re‑checking never replays side effects, supersets rest once per round on the longest member's rest, per‑exercise rest overrides work, drop‑sets and rest‑pause bursts log on the set row, and an exercise can be reordered or swapped mid‑session.

**Architecture:** Pure decision helpers in `FitnessCore` (`SupersetFlow`, `SetRowOps`), driven by `SessionRunner` (`@MainActor @Observable`). The rest‑timer and work‑timer state machine lives in a `WorkoutTimers` `@Observable`. Views (`SessionFocusView`, new sub‑rows) are thin.

**Reference:** `~/Documents/person/opengym/frontend/src/lib/supersetFlow.js`, `workout-model.js`, `active-workout-order.js`, `active-exercise-swap.js`; `store/useUI.js` (rest/work timer); `views/Workout.jsx` (wiring). Read the JSDoc in `supersetFlow.js` for the uneven‑round and re‑check rules.

## Global Constraints

Phase 3 spec. Depends on **3a** (warm‑up rows). `FitnessCore` helpers pure + Swift‑Testing. App runner changes are `@MainActor`. Snapshot types already carry `drops`/`clusters` — use them.

## File Structure

- Create `FitnessCore/Sources/RuleEngine/SupersetFlow.swift` — pure flow decisions.
- Create `FitnessCore/Sources/RuleEngine/SetRowOps.swift` — drop/cluster add/remove/patch, suggested next values, burst split.
- Create `FitnessTracker/FitnessTracker/Session/WorkoutTimers.swift` — `@Observable` rest + work timers.
- Modify `FitnessTracker/FitnessTracker/Session/SessionRunner.swift` — high‑water tracking, rest decisions via `SupersetFlow`, reorder unit, swap exercise, per‑exercise rest.
- Modify `FitnessTracker/FitnessTracker/Features/Session/SessionFocusView.swift` — sub‑rows for drop/cluster, swap/reorder controls, work‑timer UI.
- Create `FitnessTracker/FitnessTracker/Features/Session/DropSetRow.swift`, `RestPauseRow.swift`.
- Modify `FitnessTracker/FitnessTracker/Models/SessionModels.swift` + `Metrics/ModelSnapshotMapping.swift` — persist `restSec` per entry, `type`/`drops`/`clusters` per set (extend, `MetricSnapshots` already models them).
- Tests: `SupersetFlowTests.swift`, `SetRowOpsTests.swift`, `WorkoutTimersTests.swift`, extend `SessionRunnerTests.swift`.

---

## Task 1: `SupersetFlow` — pure decisions

**Files:** create `SupersetFlow.swift`; test `SupersetFlowTests.swift`.

```swift
public enum SupersetFlow {
    /// Group consecutive entries sharing a superset id into units of indices.
    public static func units(_ entries: [RunnerEntry]) -> [[Int]]
    /// First unfinished unit after `from`, wrapping once.
    public static func nextUnfinishedUnit(_ entries: [RunnerEntry], units: [[Int]], from: Int) -> [Int]?
    /// Insert index after the unit containing `current` (clamped to count).
    public static func insertionIndexAfterUnit(units: [[Int]], current: Int, entryCount: Int) -> Int
    /// New progress only when done-set count exceeds the session high-water for this entry.
    public static func progress(entry: RunnerEntry, previousHighWater: Int) -> (isNew: Bool, highWater: Int)
    /// Whether completing a set starts a rest: after every set EXCEPT the last set of the last unit.
    public static func restAfterSet(unitDone: Bool, lastUnit: Bool) -> Bool
    /// Whether re-checking a done set starts a rest: only when no timer is running and restAfterSet would.
    public static func restOnRecheck(timerRunning: Bool, unitDone: Bool, lastUnit: Bool) -> Bool
    /// Rest seconds for a completed set's unit: the LONGEST per-entry `restSec` among the
    /// unit's members, falling back to `defaultRestSec`. `defaultRestSec == 0` = off, but a
    /// per-entry value still fires.
    public static func restSeconds(entries: [RunnerEntry], unit: [Int], defaultRestSec: Int) -> Int
    /// Next index within a superset unit after finishing `from`: skips spent members, wraps,
    /// reports `roundDone` / `unitDone`.
    public static func step(entries: [RunnerEntry], unit: [Int], from: Int) -> (unitDone: Bool, roundDone: Bool, nextIdx: Int?)?
}
```
`RunnerEntry` = `{ id, supersetID: String?, restSec: Int?, sets: [SetRow] }` where `SetRow` has `done: Bool`. Define minimally in this file (mirrors the app's runner entry).

- [ ] Tests (from `supersetFlow.js` JSDoc):
  - `restAfterSet(unitDone: true, lastUnit: false)` → true (a rest belongs before the next exercise)
  - `restAfterSet(unitDone: true, lastUnit: true)` → false (session over)
  - `restAfterSet(unitDone: false, ...)` → true
  - `restOnRecheck`: timer running → false; timer idle + would‑rest → true
  - `progress`: 2 done then uncheck→recheck the same set → `isNew == false`; completing an added 3rd set → `isNew == true`
  - `restSeconds`: unit [A(restSec 90), B(restSec 180)] → 180; unit [A(nil), B(nil)], default 90 → 90; default 0, B(120) → 120
  - `step`: 2‑member unit, finish member 0 with member 1 having work → `nextIdx == 1`, `roundDone == false`; finish member 1 (last with work) → `roundDone == true`; both members spent → `unitDone == true`
  - `nextUnfinishedUnit` wraps past the end to an earlier unfinished unit
- [ ] Implement; `swift test --filter SupersetFlow` green.
- [ ] Commit `Add SupersetFlow: rest-after-set, high-water, restSeconds, step`.

## Task 2: `SetRowOps` — drop‑sets & rest‑pause on the row

**Files:** create `SetRowOps.swift`; test `SetRowOpsTests.swift`.

```swift
public enum SetRowKind: String, Sendable, Codable { case straight, dropset, restpause }
public enum SetRowOps {
    public static func addDrop(to set: LoggedSetSnapshot, loadKg: Double, reps: Int) -> LoggedSetSnapshot
    public static func addCluster(to set: LoggedSetSnapshot, reps: Int, restSec: Int) -> LoggedSetSnapshot
    public static func removeDrop(from set: LoggedSetSnapshot, at i: Int) -> LoggedSetSnapshot   // last one → back to .straight
    public static func removeCluster(from set: LoggedSetSnapshot, at i: Int) -> LoggedSetSnapshot
    public static func setDrop(_ set: LoggedSetSnapshot, at i: Int, loadKg: Double?, reps: Int?) -> LoggedSetSnapshot
    public static func setCluster(_ set: LoggedSetSnapshot, at i: Int, reps: Int?, restSec: Int?) -> LoggedSetSnapshot
    public static func nextDropLoad(previousKg: Double, pct: Double = 20) -> Double    // −pct%, round to 0.5
    public static func nextBurstReps(previous: Int) -> Int                            // ≈ half, min 1
    public static func splitBurstReps(total: Int) -> [Int]                            // 12 → [6,3,2,1]
    /// Extra volume ONLY from a drop-set's drops. Rest-pause `clusters` are already inside
    /// the row's own reps — never add them here (double count).
    public static func extraVolume(_ set: LoggedSetSnapshot) -> Double
}
```
`LoggedSetSnapshot` already has `drops: [DropSetEntry]`, `clusters: [RestPauseCluster]`, `isDropSet`. Add a `kind: SetRowKind` (default `.straight`, derived from `drops`/`clusters` non‑empty for back‑compat). Progression and 1RM keep reading only the row's own `actualLoadKg`/`actualReps` (the heaviest effort) — `extraVolume` feeds totals/volume charts only.

- [ ] Tests: `addDrop` marks `.dropset`; removing the last drop → `.straight`; `nextDropLoad(100) == 80`; `nextDropLoad(101, 20) == 80.5`; `nextBurstReps(7) == 4` (round); `splitBurstReps(12) == [6,3,2,1]` and sums to 12; `extraVolume` counts drops only; a rest‑pause row's `extraVolume == 0`.
- [ ] Implement; green; commit `Add SetRowOps: drop-set + rest-pause row ops, extraVolume`.

## Task 3: `WorkoutTimers` — rest + work timer state machine

**Files:** create `WorkoutTimers.swift`; test `WorkoutTimersTests.swift`.

`@Observable final class WorkoutTimers` (`@MainActor`). Two never‑simultaneous countdowns:
- **rest**: `start(sec:forEntryIndex:)`, `add(sec:)` (going ≤ 0 = "ready now" → stop), `stop()`, `shiftOwner(at:delta:)` (list changed shape → keep `forEntryIndex` pointing at the same entry). Beeps at ≤ 3 s and 0; haptic + optional screen‑flash at 0; schedules a `UNUserNotificationCenter` local notification for when the app is backgrounded, cancels it on stop/skip.
- **work** (timed holds): `startWork(sec:label:onDone:)`, `finishEarly()` (logs *elapsed*, not the target — a 0:38 of 0:45 hold records 0:38), `stopWork()` (abandon, log nothing). No notification (you're watching it). Starting work stops any rest.
- Tick off a `Timer` plus a `scenePhase`/`willEnterForeground` recompute from `endsAt` so a backgrounded countdown is correct on return.

Extract the tickable core (`remaining(at:)`, transition detection) as a pure function so it's tested without a run loop.

- [ ] Tests (pure core): `remaining` from `endsAt` clamps at 0; `add(-100)` when 30 left → stop; `finishEarly` at t=38 of 45 → `onDone(38)`; work reaching 0 → `onDone(45)`; starting work while a rest runs → rest stopped.
- [ ] Implement; green; commit `Add WorkoutTimers: rest + work countdown state machine`.

## Task 4: Wire `SessionRunner` to `SupersetFlow` + high‑water + per‑entry rest

**Files:** `SessionRunner.swift`, `SessionModels.swift`, `ModelSnapshotMapping.swift`; extend `SessionRunnerTests.swift`.

- `RunnerEntry` gains `restSec: Int?` (from the routine item / `target.restSec`), persisted on `CompletedEntryModel`.
- On a set toggle → done: compute `units`, the entry's unit, `unitDone`, `lastUnit`; `progress(entry:previousHighWater:)`; if `isNew`:
  - if `restAfterSet(unitDone:lastUnit:)` → `timers.startRest(SupersetFlow.restSeconds(entries:unit:defaultRestSec: settings.restSec), forEntryIndex:)`
  - superset: advance `currentEntryIndex` via `step(...)` / `nextUnfinishedUnit(...)`; plain exercise: advance to `nextUnfinishedUnit`
  - if the whole session's work is done → present the finish/continue prompt (do **not** auto‑finish)
- On a set toggle → un‑done: no side effects. On re‑check of an already‑done set: `restOnRecheck(timerRunning:unitDone:lastUnit:)`.
- Keep `previousHighWater` per entry index in the runner (reset on start).

- [ ] Tests: 2‑set exercise logs **two** rests (not one); uncheck+recheck last set with a timer running → no new rest, no re‑navigation; superset A/B logs one rest after B per round; finishing the last set of the last exercise starts **no** rest and shows the finish prompt.
- [ ] Commit `SessionRunner: SupersetFlow rest decisions + high-water + per-entry restSec`.

## Task 5: Mid‑workout reorder + swap

**Files:** create `FitnessCore/Sources/RuleEngine/ActiveWorkoutEdits.swift`; `SessionRunner.swift`; tests.

```swift
public enum ActiveWorkoutEdits {
    public static func canMoveUnit(entries: [RunnerEntry], index: Int, direction: Int) -> Bool
    public static func moveUnit(entries: inout [RunnerEntry], index: Int, direction: Int) -> (newOrder: [Int], newCurrent: Int)?
    public enum SwapResult { case replacedInPlace(index: Int)
                             case needsConfirmation(grouped: Bool, index: Int)
                             case inserted(index: Int) }
    public static func swap(entries: inout [RunnerEntry], index: Int, replacement: RunnerEntry,
                            loggedConfirmed: Bool, groupDisposition: GroupDisposition?) -> SwapResult
    public enum GroupDisposition { case keep, detach }
}
```
Rules: moving a *unit* (superset group moves as one) up/down, keeping `currentEntryIndex` on the same entry. Swap: if the target has no done set → replace in place, preserving the entry's metadata (notes, feel) and its `supersetID`. If it has a done set → `needsConfirmation`; on confirm, **insert** the replacement beside the original (never relabel logged work); for a grouped member, require `keep` (stay in group) or `detach` (after the group).

`SessionRunner` exposes `moveUnit(entryIndex:direction:)`, `swap(entryIndex:to:)` calling into these, then re‑numbers `performedOrder` and persists.

- [ ] Tests: move a plain exercise down past a superset unit → the superset stays contiguous; swap an unlogged exercise → replaced, `supersetID` kept, `currentEntryIndex` follows; swap a logged exercise without confirm → `needsConfirmation`; with confirm → original kept + replacement inserted after; grouped + `keep` vs `detach` insertion positions.
- [ ] Commit `Add ActiveWorkoutEdits: reorder unit + swap exercise (logged-safe)`.

## Task 6: Views — sub‑rows, controls, work‑timer UI

**Files:** `SessionFocusView.swift`, `DropSetRow.swift`, `RestPauseRow.swift`, `PlateMathSheet.swift` (trigger), tests are a UI smoke.

- A set row can expand a `.subrow` stack: drop entries (weight/reps steppers) or rest‑pause bursts (reps/rest steppers), with `+ drop` / `+ burst` seeded from `SetRowOps.nextDropLoad` / `nextBurstReps`.
- Header: "Swap exercise", unit up/down chevrons (from Task 5), a per‑exercise rest field, a plate‑math button (opens `PlateMathSheet` with `PlateMath.plateSplit`).
- Work‑timer overlay for timed holds: circular countdown, "finish early" (logs elapsed), driven by `WorkoutTimers`.
- Compact "all exercises" list + focused current card (openGym's two‑pane runner).

- [ ] Build + one XCUITest smoke: start → log a set → drop row add/remove → rest timer appears → finish prompt.
- [ ] Commit `SessionFocusView: drop/rest-pause sub-rows, swap/reorder, work timer, plate math`.

## Task 7: Suite sweep

- [ ] `cd FitnessCore && swift test` + `xcodebuild test …` green.
- [ ] Commit `Phase 3c: suites green`.

## Self‑review

Coverage: rest‑after‑every‑set ✅(T1/T4), high‑water re‑check guard ✅(T1/T4), superset longest‑rest + step ✅(T1/T4), per‑exercise rest ✅(T4), drop/rest‑pause on row + extraVolume‑totals‑only ✅(T2/T6), reorder + logged‑safe swap ✅(T5/T6), work timer logs elapsed ✅(T3/T6). Types: `RunnerEntry`/`SetRow` defined in T1, reused T2/T4/T5.
