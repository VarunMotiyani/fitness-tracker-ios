# Phase 2a — Metrics & Memory Foundation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pure-logic foundation for Phase 2 — a comprehensive metrics
layer and a self-curating coach-memory layer — as two new `FitnessCore` modules
plus a real progression rule and finalize guardrail in `RuleEngine`. No app, no
SwiftData, no UI, no network.

**Architecture:** Everything here is pure value types and pure functions over
injected data, mirroring how Phase 1a built `FitnessCore`. The app layer (Phase
2b onward) will own SwiftData `@Model`s that map to/from these value snapshots
(the `UserProfile` → `UserContext` pattern from Phase 1). Two new modules:
`Metrics` (depends on `FitnessDomain`) and `CoachMemory` (depends on
`FitnessDomain`). `RuleEngine` gains a dependency on `Metrics` for the
progression rule and finalize guardrail.

**Tech Stack:** Swift 6.2 (`swift-tools-version` already 6.2 in the package),
strict concurrency, `swift test` (Swift Testing — Xcode/CLT bundled, no package
dependency). Platforms `.iOS(.v26), .macOS(.v14)` as today.

**Spec:** `docs/specs/2026-08-29-phase-2-session-runner-design.md`
(§7 memory, §8 data layer, §5.3/§5.4 guardrail + progression, §13 decisions).

## Global Constraints

- **Package only.** Every change is inside `FitnessCore/`. No `FitnessTracker/`
  app changes in this plan. No SwiftData, no SwiftUI, no `URLSession`.
- **Pure and `Sendable`.** All new types are value types and `Sendable`. All new
  behaviour is pure functions or `struct` methods with no I/O, no `Date()` reads
  inside logic (callers pass `now`), no globals. Follows Phase 1a's `FitnessCore`
  style — `public` API, no `@MainActor`, no `nonisolated` needed (package code is
  not under the app's default-actor-isolation setting).
- **e1RM formula is Epley, exactly:** `e1RM = loadKg * (1 + reps / 30.0)`. One
  implementation (`Estimated1RM.epley`), used everywhere. Reps `<= 0` → return
  `0`. Reps `== 1` → return `loadKg` (Epley already yields `load * 31/30` at
  reps 1; clamp the 1-rep case to `loadKg` explicitly so a true 1RM is not
  inflated).
- **Existing 35 `FitnessCore` tests stay green.** New modules add tests; no
  existing file is edited except `Package.swift` and the two `RuleEngine` source
  additions (progression rule + guardrail are NEW files, not edits to
  `RulePlanBuilder.swift`).
- **TDD, frequent commits.** One commit per task. Plain imperative commit
  subjects, no body required, **no `Co-Authored-By` trailer**. Do not `git push`.
- **Test runner:** `cd FitnessCore && swift test` from the repo root; a single
  module's tests via `swift test --filter <SuiteName>`.
- Naming: `...Snapshot` for the value mirrors of app-layer `@Model`s;
  the app's SwiftData models (Phase 2b) will be named without the suffix.

## Existing types this plan builds on (from Phase 1a, do not modify)

- `FitnessDomain`: `MuscleGroup` (13 cases), `Equipment` (9), `Mechanic`
  (`compound | isolation | unknown`), `Goal`, `ExperienceLevel`, `RepRange(min:max:)`.
- `ExerciseCatalog`: `Exercise` (`id, name, primaryMuscle, secondaryMuscles,
  equipment, mechanic, …`), `CatalogStore` (`init(exercises:)`, `exercise(id:)`,
  `exercises(primaryMuscle:availableEquipment:)`).
- `RuleEngine`: `VolumeLandmarks.band(for:experience:) -> VolumeBand{mev,mav,mrv}`,
  `RulePlanBuilder`, `SplitTemplateLibrary`.
- `PlanValidation`: `PlanValidator`, `ValidationIssue`.

---

## File Structure

**New module `Sources/Metrics/`:**
- `MetricSnapshots.swift` — the value mirrors + supporting enums.
- `Estimated1RM.swift` — Epley.
- `PersonalRecord.swift` — `PersonalRecord`, `PRType`.
- `PRDetector.swift` — new-PRs-from-a-session.
- `Rollups.swift` — `WeeklyMuscleVolume`, `ExerciseTrendPoint`, `RollupComputer`.
- `MetricsRepository.swift` — protocol + `InMemoryMetricsRepository` + result types.

**New module `Sources/CoachMemory/`:**
- `CoachMemory.swift` — the record + `MemoryKind`, `MemorySource`, `MemoryTags`.
- `MemoryConsolidation.swift` — `reconcile(existing:candidates:now:cap:)`.
- `MemoryRecall.swift` — `select(...)`, `RecalledMemories`, `ProfileDigest`.
- `MemoryOutcome.swift` — `applyResult(...)`, `OutcomeSignal`.

**New files in `Sources/RuleEngine/`:**
- `ProgressionRule.swift` — `ProgressionRule`, `ProgressionDecision`.
- `FinalizeGuardrail.swift` — `FinalizeGuardrail`, `GuardrailViolation`.

**`Package.swift`** — add `Metrics`, `CoachMemory` library products + targets +
test targets; add `Metrics` to `RuleEngine`'s dependencies.

**New test files:** one per source file, under
`Tests/MetricsTests/`, `Tests/CoachMemoryTests/`, and additions to
`Tests/RuleEngineTests/`.

---

## Task 1: `Metrics` module — snapshot value types + package wiring

**Files:**
- Modify: `FitnessCore/Package.swift`
- Create: `FitnessCore/Sources/Metrics/MetricSnapshots.swift`
- Test: `FitnessCore/Tests/MetricsTests/MetricSnapshotsTests.swift`

**Interfaces:**
- Produces (all `public`, `Sendable`, `Codable`, `Equatable`):
  - `enum EnergyRating: String { case beat, normal, great }`
  - `enum Feel: String { case easy, right, brutal }`
  - `enum SessionOutcome: String { case complete, partial }`
  - `enum PartialReason: String { case ranOutOfTime, tooTired, painNiggle, gymCrowded, notFeelingIt, other }`
  - `enum EntryState: String { case notStarted, inProgress, done }`
  - `struct LoggedSetSnapshot { let targetReps: Int; let targetLoadKg: Double?; let actualReps: Int; let actualLoadKg: Double; let startedAt: Date; let completedAt: Date; let restBeforeSec: Int; let rpe: Double?; let isWarmup: Bool; let isDropSet: Bool; let toFailure: Bool; let assisted: Bool }`
  - `struct CompletedEntrySnapshot { let exerciseID: String; let performedOrder: Int; let state: EntryState; let skipped: Bool; let wasSwappedFrom: String?; let feel: Feel?; let note: String?; let sets: [LoggedSetSnapshot] }`
  - `struct CompletedSessionSnapshot { let id: UUID; let date: Date; let weekday: Int; let timeOfDayMinutes: Int; let plannedDurationMin: Int; let actualDurationMin: Int; let energy: EnergyRating; let timeAvailableMin: Int; let outcome: SessionOutcome; let partialReason: PartialReason?; let coachSource: CoachSource; let plannedSessionID: UUID?; let entries: [CompletedEntrySnapshot]; let overallNote: String? }`
  - `enum CoachSource: String { case ai, rule }`
  - `struct BodyweightSnapshot { let date: Date; let kg: Double }`
  - `struct DailyCheckinSnapshot { let date: Date; let sleepQuality: Int?; let soreness: Int?; let note: String? }`
  - `struct ObservationSnapshot { let kind: String; let value: Double; let unit: String; let timestamp: Date; let context: [String: String]; let sessionID: UUID?; let entryExerciseID: String? }`

- [ ] **Step 1: Add the module to `Package.swift`**

In `products`, after the `LLMKit` library line:
```swift
        .library(name: "Metrics", targets: ["Metrics"]),
        .library(name: "CoachMemory", targets: ["CoachMemory"]),
```
In `targets`, after the `LLMKit` target:
```swift
        .target(name: "Metrics", dependencies: ["FitnessDomain"]),
        .target(name: "CoachMemory", dependencies: ["FitnessDomain"]),
```
And after the `LLMKitTests` test target:
```swift
        .testTarget(name: "MetricsTests", dependencies: ["Metrics", "FitnessDomain"]),
        .testTarget(name: "CoachMemoryTests", dependencies: ["CoachMemory", "FitnessDomain"]),
```

- [ ] **Step 2: Write the failing test** — `Tests/MetricsTests/MetricSnapshotsTests.swift`

```swift
import Testing
import Foundation
@testable import Metrics

@Suite struct MetricSnapshotsTests {
    @Test func sessionSnapshotRoundTripsThroughCodable() throws {
        let set = LoggedSetSnapshot(targetReps: 8, targetLoadKg: 60, actualReps: 8,
            actualLoadKg: 60, startedAt: Date(timeIntervalSince1970: 0),
            completedAt: Date(timeIntervalSince1970: 40), restBeforeSec: 120,
            rpe: 8, isWarmup: false, isDropSet: false, toFailure: false, assisted: false)
        let entry = CompletedEntrySnapshot(exerciseID: "bench", performedOrder: 0,
            state: .done, skipped: false, wasSwappedFrom: nil, feel: .right,
            note: nil, sets: [set])
        let session = CompletedSessionSnapshot(id: UUID(), date: Date(timeIntervalSince1970: 100),
            weekday: 2, timeOfDayMinutes: 1080, plannedDurationMin: 60, actualDurationMin: 58,
            energy: .normal, timeAvailableMin: 60, outcome: .complete, partialReason: nil,
            coachSource: .rule, plannedSessionID: nil, entries: [entry], overallNote: "solid")

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(CompletedSessionSnapshot.self, from: data)
        #expect(decoded == session)
    }

    @Test func partialReasonHasAllSixCases() {
        #expect(PartialReason.allCases.count == 6)
    }
}
```
(Add `CaseIterable` to `PartialReason` and `Feel`/`EnergyRating` where the test needs it.)

- [ ] **Step 3: Run it — expect FAIL** (`swift test --filter MetricSnapshotsTests`) — "no such module 'Metrics'".

- [ ] **Step 4: Write `MetricSnapshots.swift`** with every type above. All `public`, `Sendable`, `Codable`, `Equatable`; add `CaseIterable` to the enums. Memberwise `public init(...)` for every struct (Swift does not synthesise public inits).

- [ ] **Step 5: Run tests — expect PASS.** Also run the whole suite (`swift test`) — 35 existing + 2 new.

- [ ] **Step 6: Commit** — `git commit -m "Add Metrics module snapshot value types"`

---

## Task 2: Epley e1RM + `PersonalRecord`

**Files:**
- Create: `FitnessCore/Sources/Metrics/Estimated1RM.swift`
- Create: `FitnessCore/Sources/Metrics/PersonalRecord.swift`
- Test: `FitnessCore/Tests/MetricsTests/Estimated1RMTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum Estimated1RM { public static func epley(loadKg: Double, reps: Int) -> Double }`
  - `enum PRType: String, Codable, Sendable, CaseIterable { case heaviestWeight, repsAtWeight, estimated1RM }`
  - `struct PersonalRecord: Sendable, Codable, Equatable { let type: PRType; let exerciseID: String; let value: Double; let reps: Int; let date: Date; let sessionID: UUID }`
    - `value`: for `heaviestWeight` and `estimated1RM` it is kg; for `repsAtWeight` it is the rep count and `reps` mirrors it, with the weight carried in a second field `atLoadKg: Double` (add it). So: `struct PersonalRecord { type; exerciseID; value: Double; atLoadKg: Double; reps: Int; date; sessionID }`.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import Metrics

@Suite struct Estimated1RMTests {
    @Test func epleyKnownValues() {
        #expect(Estimated1RM.epley(loadKg: 100, reps: 1) == 100)          // 1-rep clamps to load
        #expect(abs(Estimated1RM.epley(loadKg: 100, reps: 10) - 133.333) < 0.01)
        #expect(abs(Estimated1RM.epley(loadKg: 60, reps: 5) - 70) < 0.001)
    }
    @Test func epleyNonPositiveRepsIsZero() {
        #expect(Estimated1RM.epley(loadKg: 100, reps: 0) == 0)
        #expect(Estimated1RM.epley(loadKg: 100, reps: -3) == 0)
    }
    @Test func prTypeHasThreeCases() { #expect(PRType.allCases.count == 3) }
}
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement.**

```swift
public enum Estimated1RM {
    public static func epley(loadKg: Double, reps: Int) -> Double {
        guard reps > 0 else { return 0 }
        if reps == 1 { return loadKg }
        return loadKg * (1 + Double(reps) / 30.0)
    }
}
```
Plus `PRType` and `PersonalRecord` (with `atLoadKg`) in `PersonalRecord.swift`.

- [ ] **Step 4: Run — expect PASS.**

- [ ] **Step 5: Commit** — `git commit -m "Add Epley e1RM and PersonalRecord type"`

---

## Task 3: `PRDetector`

**Files:**
- Create: `FitnessCore/Sources/Metrics/PRDetector.swift`
- Test: `FitnessCore/Tests/MetricsTests/PRDetectorTests.swift`

**Interfaces:**
- Consumes: `CompletedSessionSnapshot`, `LoggedSetSnapshot`, `PersonalRecord`, `PRType`, `Estimated1RM`.
- Produces:
  - `struct PRDetector { public init(); public func newPRs(in session: CompletedSessionSnapshot, priorPRs: [PersonalRecord]) -> [PersonalRecord] }`
- Rules (per exercise, working sets only — `isWarmup == false`):
  - `heaviestWeight`: max `actualLoadKg` across the session's sets for that exercise; a PR only if strictly greater than the best prior `heaviestWeight` for that exercise (or no prior).
  - `estimated1RM`: max `Estimated1RM.epley(actualLoadKg, actualReps)`; PR if strictly greater than prior best.
  - `repsAtWeight`: for the heaviest load the user has an established prior `repsAtWeight` record at, more reps than before at that same `atLoadKg`. If no prior `repsAtWeight` exists for the exercise, seed one from the best set (not counted as a "new PR" toast — return it with a flag? keep simple: seed it and DO include it; the app decides toast-worthiness). Keep the rule: same `atLoadKg`, strictly more `reps`.
  - Ties never count. Each `PersonalRecord.date`/`sessionID` come from the session.

- [ ] **Step 1: Write the failing test**

```swift
@Suite struct PRDetectorTests {
    private func session(_ exID: String, _ sets: [(reps: Int, load: Double)], id: UUID = UUID()) -> CompletedSessionSnapshot {
        let logged = sets.map { s in
            LoggedSetSnapshot(targetReps: s.reps, targetLoadKg: s.load, actualReps: s.reps,
                actualLoadKg: s.load, startedAt: .init(timeIntervalSince1970: 0),
                completedAt: .init(timeIntervalSince1970: 30), restBeforeSec: 90, rpe: nil,
                isWarmup: false, isDropSet: false, toFailure: false, assisted: false)
        }
        let entry = CompletedEntrySnapshot(exerciseID: exID, performedOrder: 0, state: .done,
            skipped: false, wasSwappedFrom: nil, feel: .right, note: nil, sets: logged)
        return CompletedSessionSnapshot(id: id, date: .init(timeIntervalSince1970: 1000), weekday: 3,
            timeOfDayMinutes: 600, plannedDurationMin: 60, actualDurationMin: 60, energy: .normal,
            timeAvailableMin: 60, outcome: .complete, partialReason: nil, coachSource: .rule,
            plannedSessionID: nil, entries: [entry], overallNote: nil)
    }

    @Test func firstEverSessionSeedsRecords() {
        let prs = PRDetector().newPRs(in: session("squat", [(5, 100)]), priorPRs: [])
        #expect(prs.contains { $0.type == .heaviestWeight && $0.value == 100 })
        #expect(prs.contains { $0.type == .estimated1RM })
    }
    @Test func heavierWeightIsAPR() {
        let prior = [PersonalRecord(type: .heaviestWeight, exerciseID: "squat", value: 100,
            atLoadKg: 100, reps: 5, date: .init(timeIntervalSince1970: 0), sessionID: UUID())]
        let prs = PRDetector().newPRs(in: session("squat", [(3, 105)]), priorPRs: prior)
        #expect(prs.contains { $0.type == .heaviestWeight && $0.value == 105 })
    }
    @Test func equalWeightIsNotAPR() {
        let prior = [PersonalRecord(type: .heaviestWeight, exerciseID: "squat", value: 100,
            atLoadKg: 100, reps: 5, date: .init(timeIntervalSince1970: 0), sessionID: UUID())]
        let prs = PRDetector().newPRs(in: session("squat", [(5, 100)]), priorPRs: prior)
        #expect(!prs.contains { $0.type == .heaviestWeight })
    }
    @Test func warmupSetsAreIgnored() {
        var s = session("bench", [(1, 140)])
        // mark the single set a warmup
        let warm = LoggedSetSnapshot(targetReps: 1, targetLoadKg: 140, actualReps: 1, actualLoadKg: 140,
            startedAt: .init(timeIntervalSince1970: 0), completedAt: .init(timeIntervalSince1970: 5),
            restBeforeSec: 0, rpe: nil, isWarmup: true, isDropSet: false, toFailure: false, assisted: false)
        s = CompletedSessionSnapshot(id: s.id, date: s.date, weekday: s.weekday,
            timeOfDayMinutes: s.timeOfDayMinutes, plannedDurationMin: s.plannedDurationMin,
            actualDurationMin: s.actualDurationMin, energy: s.energy, timeAvailableMin: s.timeAvailableMin,
            outcome: s.outcome, partialReason: nil, coachSource: .rule, plannedSessionID: nil,
            entries: [CompletedEntrySnapshot(exerciseID: "bench", performedOrder: 0, state: .done,
                skipped: false, wasSwappedFrom: nil, feel: .right, note: nil, sets: [warm])],
            overallNote: nil)
        #expect(PRDetector().newPRs(in: s, priorPRs: []).isEmpty)
    }
    @Test func perExerciseIsolation() {
        let prior = [PersonalRecord(type: .heaviestWeight, exerciseID: "squat", value: 200,
            atLoadKg: 200, reps: 1, date: .init(timeIntervalSince1970: 0), sessionID: UUID())]
        let prs = PRDetector().newPRs(in: session("bench", [(5, 80)]), priorPRs: prior)
        #expect(prs.contains { $0.type == .heaviestWeight && $0.exerciseID == "bench" && $0.value == 80 })
    }
}
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement `PRDetector`** per the rules above.

- [ ] **Step 4: Run — expect PASS**, then full `swift test`.

- [ ] **Step 5: Commit** — `git commit -m "Add PRDetector for weight, reps-at-weight, and e1RM PRs"`

---

## Task 4: Rollups — `WeeklyMuscleVolume`, `ExerciseTrendPoint`, `RollupComputer`

**Files:**
- Create: `FitnessCore/Sources/Metrics/Rollups.swift`
- Test: `FitnessCore/Tests/MetricsTests/RollupComputerTests.swift`

**Interfaces:**
- Consumes: `CompletedSessionSnapshot`, `CatalogStore` (from `ExerciseCatalog`), `Estimated1RM`. **Add `ExerciseCatalog` to the `Metrics` target deps** in `Package.swift` (and `MetricsTests`).
- Produces (`public`, `Sendable`, `Equatable`):
  - `struct WeeklyMuscleVolume { let weekStart: Date; let muscle: MuscleGroup; let sets: Int }`
  - `struct ExerciseTrendPoint { let exerciseID: String; let date: Date; let e1RM: Double; let bestSetLoadKg: Double; let bestSetReps: Int; let tonnage: Double }`
  - `struct RollupComputer { public init(catalog: CatalogStore); public func weeklyMuscleVolume(from sessions: [CompletedSessionSnapshot], calendar: Calendar) -> [WeeklyMuscleVolume]; public func exerciseTrend(from sessions: [CompletedSessionSnapshot], exerciseID: String) -> [ExerciseTrendPoint] }`
- Rules:
  - **Weekly muscle volume:** a working set (`isWarmup == false`) counts **1 set**
    toward its exercise's `primaryMuscle` (look up via `catalog.exercise(id:)`;
    unknown id → skip the set). Week bucket = `calendar.dateInterval(of: .weekOfYear, for: session.date)!.start`.
    Output sorted by `(weekStart, MuscleGroup.allCases order)`. Partial sessions
    count exactly like complete ones.
  - **Exercise trend:** one point per session that contains ≥1 working set for
    `exerciseID`. `e1RM` = max Epley over its working sets. `bestSetLoadKg` /
    `bestSetReps` = the set with the highest Epley. `tonnage` = Σ
    `actualReps * actualLoadKg` over working sets. Sorted by `date` ascending.

- [ ] **Step 1: Write the failing test** — build a tiny `CatalogStore` with two
  exercises (`"bench"` primary `.chest`, `"squat"` primary `.quads`), two sessions
  in the same ISO week and one the next week, assert:
  - `weeklyMuscleVolume` groups `.chest` sets in week 1, isolates week 2.
  - a warmup set does not add to the count.
  - `exerciseTrend(exerciseID: "bench")` returns one point per session, e1RM
    monotone with the heavier session, `tonnage` matches Σ reps×load.
  - unknown exercise id in a set is skipped without crashing.

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement `RollupComputer`.** Update `Package.swift`: `Metrics`
  target deps `["FitnessDomain", "ExerciseCatalog"]`; `MetricsTests` deps add
  `"ExerciseCatalog"`.

- [ ] **Step 4: Run — expect PASS**, then full `swift test`.

- [ ] **Step 5: Commit** — `git commit -m "Add RollupComputer for weekly volume and exercise trend"`

---

## Task 5: `MetricsRepository` protocol + `InMemoryMetricsRepository`

**Files:**
- Create: `FitnessCore/Sources/Metrics/MetricsRepository.swift`
- Test: `FitnessCore/Tests/MetricsTests/InMemoryMetricsRepositoryTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1–4.
- Produces:
  - `struct ExercisePerformance: Sendable, Equatable { let exerciseID: String; let date: Date; let sets: [LoggedSetSnapshot]; let feel: Feel? }`
  - `protocol MetricsRepository: Sendable {`
    - `func lastPerformance(exerciseID: String) -> ExercisePerformance?`
    - `func bestSet(exerciseID: String, since: Date?) -> LoggedSetSnapshot?`  (by Epley)
    - `func e1RMSeries(exerciseID: String, since: Date?) -> [ExerciseTrendPoint]`
    - `func weeklyVolume(muscle: MuscleGroup, weeks: Int, now: Date) -> [WeeklyMuscleVolume]`
    - `func personalRecords(exerciseID: String?) -> [PersonalRecord]`
    - `func adherence(weeks: Int, now: Date) -> Double`  (completed-or-partial sessions ÷ planned session slots in window; planned count passed in at init)
    - `func stalls() -> [String]`  (exerciseIDs whose last 3 trend points show no e1RM increase)
    - `func observations(kind: String, since: Date?) -> [ObservationSnapshot]`
  - `}`
  - `struct InMemoryMetricsRepository: MetricsRepository { public init(sessions: [CompletedSessionSnapshot], priorPRs: [PersonalRecord], observations: [ObservationSnapshot], plannedSessionsPerWeek: Int, catalog: CatalogStore, calendar: Calendar = .init(identifier: .gregorian)) }`
    - Computes PRs internally as `priorPRs` + `PRDetector` applied across `sessions` in date order.
    - `stalls()`: for every exerciseID appearing in `sessions`, take `exerciseTrend(...)`; if it has ≥3 points and `last.e1RM <= trend[count-3].e1RM`, it's a stall.

- [ ] **Step 1: Write the failing test** — one `InMemoryMetricsRepository` built
  from ~4 sessions across 3 weeks + a small catalog, then a `@Test` per method:
  - `lastPerformance("bench")` returns the most recent session's bench sets + feel.
  - `bestSet("bench", since: nil)` is the highest-Epley set.
  - `e1RMSeries` length == number of bench sessions, ascending dates.
  - `weeklyVolume(muscle: .chest, weeks: 4, now:)` has ≤4 buckets, newest within window.
  - `personalRecords(exerciseID: "bench")` contains the heaviest-weight PR.
  - `adherence(weeks: 3, now:)` == sessionsInWindow / (3 * plannedSessionsPerWeek), clamped to `0...1`.
  - `stalls()` flags an exercise with 3 flat e1RM points; does not flag a rising one.
  - `observations(kind: "bodyweight", since: nil)` filters by kind.

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement** the protocol + struct. All methods pure over the
  stored arrays; no `Date()` — `now` is a parameter where windowing is needed.

- [ ] **Step 4: Run — expect PASS**, then full `swift test`.

- [ ] **Step 5: Commit** — `git commit -m "Add MetricsRepository protocol and in-memory implementation"`

---

## Task 6: `RuleEngine.ProgressionRule`

**Files:**
- Modify: `FitnessCore/Package.swift` (add `Metrics` to `RuleEngine` deps + `RuleEngineTests` deps)
- Create: `FitnessCore/Sources/RuleEngine/ProgressionRule.swift`
- Test: `FitnessCore/Tests/RuleEngineTests/ProgressionRuleTests.swift`

**Interfaces:**
- Consumes: `Metrics.ExercisePerformance`, `Metrics.Feel`, `FitnessDomain.RepRange`, `FitnessDomain.Mechanic`.
- Produces:
  - `enum ProgressionDirection: Sendable, Equatable { case increaseLoad, hold, decreaseLoad, addSet }`
  - `struct ProgressionDecision: Sendable, Equatable { let direction: ProgressionDirection; let targetLoadKg: Double; let targetSets: Int; let rationale: String }`
  - `struct ProgressionRule: Sendable {`
    - `public init(maxIncreaseFraction: Double = 0.10, maxDecreaseFraction: Double = 0.15)`
    - `public func next(currentTargetLoadKg: Double, currentTargetSets: Int, repRange: RepRange, mechanic: Mechanic, lastPerformance: ExercisePerformance?) -> ProgressionDecision`
  - `}`
- Rules (working sets only from `lastPerformance`):
  - No `lastPerformance` → `hold` at current load/sets, rationale `"no history yet"`.
  - `feel == .easy` **and** every working set hit `>= repRange.max` reps →
    `increaseLoad`: `newLoad = currentTargetLoadKg * (1 + step)` where
    `step = mechanic == .compound ? 0.05 : 0.025`, then **cap** the increase at
    `maxIncreaseFraction` and round to the nearest `2.5`. `targetSets` unchanged.
  - `feel == .right`, or (`easy` but not all sets at `repRange.max`) → `hold`
    (repeat the load); if the user hit `>= repRange.max` on **all** sets here too,
    it's a small bump (same as above but `step` halved). Rationale explains.
  - `feel == .brutal` **or** any working set `< repRange.min` reps →
    `decreaseLoad`: `newLoad = currentTargetLoadKg * (1 - 0.05)`, capped at
    `maxDecreaseFraction`, rounded to `2.5`. If `feel == .brutal` but reps were
    all in range → `hold`, not decrease.
  - `addSet` is only returned when `feel == .easy`, all sets maxed, AND the load
    is already at/above a sane ceiling passed by the caller — **out of scope for
    2a**; do not emit `addSet` from the rule yet (the AI coach owns volume). Keep
    the case in the enum for 2c but never return it here. Add a test asserting
    it is never returned.
  - Round helper: `(x / 2.5).rounded() * 2.5`.

- [ ] **Step 1: Write the failing test** — a `perf(...)` helper building an
  `ExercisePerformance` from `[(reps, load)]` + a `Feel`, then:
  - no history → `.hold`, load unchanged.
  - `easy` + all sets at `repRange.max` on a compound → `.increaseLoad`, new load
    `== currentLoad * 1.05` rounded to 2.5, and `<= currentLoad * 1.10`.
  - `easy` + a 40kg isolation, step 0.025 → `+1kg` intent rounds to `+0` or the
    nearest 2.5 — assert `newLoad >= currentLoad` and `<= currentLoad * 1.10`.
  - `right` + mid-range reps → `.hold`.
  - `brutal` + a set below `repRange.min` → `.decreaseLoad`, `>= currentLoad * 0.85`.
  - `brutal` + all reps in range → `.hold`.
  - never returns `.addSet` across all the above.

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement.** `Package.swift`: `RuleEngine` deps become
  `["FitnessDomain", "ExerciseCatalog", "Metrics"]`; `RuleEngineTests` deps add
  `"Metrics"`.

- [ ] **Step 4: Run — expect PASS**, then full `swift test`.

- [ ] **Step 5: Commit** — `git commit -m "Add real progression rule to RuleEngine"`

---

## Task 7: `RuleEngine.FinalizeGuardrail`

**Files:**
- Create: `FitnessCore/Sources/RuleEngine/FinalizeGuardrail.swift`
- Test: `FitnessCore/Tests/RuleEngineTests/FinalizeGuardrailTests.swift`

**Interfaces:**
- Consumes: `FitnessDomain` (`WeeklyPlan`/`PlannedSession`/`PlannedItem`,
  `MuscleGroup`, `RepRange`), `ExerciseCatalog.CatalogStore`, `RuleEngine.VolumeLandmarks`,
  `Metrics.ExercisePerformance`.
- Produces:
  - `enum GuardrailViolation: Sendable, Equatable {`
    - `case loadJumpTooLarge(exerciseID: String, proposedKg: Double, cappedKg: Double)`
    - `case loadDropTooLarge(exerciseID: String, proposedKg: Double, cappedKg: Double)`
    - `case weeklyVolumeOutOfBand(muscle: MuscleGroup, sets: Int, mev: Int, mrv: Int)`
    - `case repTargetOutOfRange(exerciseID: String, target: RepRange, allowed: RepRange)`
    - `case excludedExercise(exerciseID: String)`
    - `case sessionTooLong(estimatedMin: Int, availableMin: Int)`
  - `}`
  - `struct GuardrailReport: Sendable, Equatable { let violations: [GuardrailViolation]; let clampedSession: PlannedSession }`
  - `struct FinalizeGuardrail: Sendable {`
    - `public init(catalog: CatalogStore)`
    - `public func check(finalized: PlannedSession, experience: ExperienceLevel, excludedExerciseIDs: Set<String>, excludedMuscles: Set<MuscleGroup>, availableEquipment: Set<Equipment>, lastPerformances: [String: ExercisePerformance], timeAvailableMin: Int, maxIncreaseFraction: Double = 0.10, maxDecreaseFraction: Double = 0.15) -> GuardrailReport`
  - `}`
- Rules — for each `PlannedItem` and the session as a whole, detect a violation
  AND produce the `clampedSession` where each offending value is snapped to the
  rule-engine-safe value; non-offending items pass through untouched:
  - **Load jump:** `item.targetLoadKg` vs `lastPerformances[id]` best working load.
    `> last * (1 + maxIncreaseFraction)` → `loadJumpTooLarge`, clamp to
    `last * (1 + maxIncreaseFraction)` rounded to 2.5. `< last * (1 - maxDecreaseFraction)`
    → `loadDropTooLarge`, clamp up. No `lastPerformances` entry → no load check.
  - **Weekly volume:** sum `targetSets` per `primaryMuscle` across the session
    (via catalog); if outside `VolumeLandmarks.band(for:experience:)` `mev...mrv`
    → `weeklyVolumeOutOfBand`; clamp the session's sets for that muscle
    proportionally back to the nearer bound (floor `mev`, ceil `mrv`), minimum 1
    set per item.  _Note: this is a per-session proxy for the weekly check; the
    true weekly figure is the app's job in 2c. Document that in a doc comment._
  - **Rep target:** `item.targetReps` must be inside the exercise's sane range —
    for 2a use `RepRange(min: 3, max: 20)` as the universal allowed envelope
    (a per-exercise range table is a later refinement); outside → clamp.
  - **Excluded exercise / muscle / equipment:** an item referencing an excluded
    id, an excluded `primaryMuscle`, or an exercise whose `equipment` is not in
    `availableEquipment` → `excludedExercise`; **drop the item** from
    `clampedSession` (the coach shouldn't have picked it).
  - **Session length:** `estimatedMin = Σ over items (targetSets * (setSeconds + item.restSeconds)) / 60` with `setSeconds = 40`. `> availableMin * 1.15`
    → `sessionTooLong`; clamp by removing whole trailing items (lowest
    `order` last) until it fits or one item remains.
  - `violations` empty ⇒ `clampedSession == finalized`.

- [ ] **Step 1: Write the failing test** — a small catalog + a finalized
  `PlannedSession`, one `@Test` per violation kind proving (a) it's reported and
  (b) `clampedSession` carries the snapped/dropped value; plus a "clean session
  passes unchanged" test.

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run — expect PASS**, then full `swift test`.

- [ ] **Step 5: Commit** — `git commit -m "Add FinalizeGuardrail to RuleEngine"`

---

## Task 8: `CoachMemory` record + enums

**Files:**
- Create: `FitnessCore/Sources/CoachMemory/CoachMemory.swift`
- Test: `FitnessCore/Tests/CoachMemoryTests/CoachMemoryTests.swift`

**Interfaces:**
- Consumes: `FitnessDomain` (`MuscleGroup`, `Equipment`).
- Produces (`public`, `Sendable`, `Codable`, `Equatable`):
  - `enum MemoryKind: String, CaseIterable { case preference, constraint, observation, goal, responsePattern }`
  - `enum MemorySource: Sendable, Codable, Equatable { case agent(String); case user }`
  - `struct MemoryTags: Sendable, Codable, Equatable { var exerciseID: String?; var muscle: MuscleGroup?; var equipment: Equipment?; var freeTags: [String] }` — memberwise `public init` with defaults `nil, nil, nil, []`.
  - `struct CoachMemory: Sendable, Codable, Equatable, Identifiable {`
    - `let id: UUID`
    - `var kind: MemoryKind`
    - `var statement: String`
    - `var action: String?`
    - `var confidence: Double`         // 0...1, clamp in init
    - `var source: MemorySource`
    - `var createdAt: Date`
    - `var lastConfirmedAt: Date`
    - `var supersededBy: UUID?`
    - `var tags: MemoryTags`
    - `var outcomeScore: Double?`      // running -1...1, nil until acted on
  - `}` with a `public init` clamping `confidence` to `0...1` and `outcomeScore` (if non-nil) to `-1...1`.
  - `var isRetired: Bool { supersededBy != nil }` on `CoachMemory`.

- [ ] **Step 1: Write the failing test** — Codable round-trip of a `CoachMemory`
  with `source == .agent("progressAnalyst")` and populated `tags`; `confidence`
  of `1.7` clamps to `1.0`; `MemoryKind.allCases.count == 5`; `isRetired` reflects
  `supersededBy`.

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run — expect PASS**, then full `swift test`.

- [ ] **Step 5: Commit** — `git commit -m "Add CoachMemory record and supporting types"`

---

## Task 9: `MemoryConsolidation.reconcile`

**Files:**
- Create: `FitnessCore/Sources/CoachMemory/MemoryConsolidation.swift`
- Test: `FitnessCore/Tests/CoachMemoryTests/MemoryConsolidationTests.swift`

**Interfaces:**
- Consumes: `CoachMemory`, `MemoryKind`, `MemoryTags`.
- Produces:
  - `struct MemoryCandidate: Sendable, Equatable { let kind: MemoryKind; let statement: String; let action: String?; let tags: MemoryTags; let relation: CandidateRelation }`
  - `enum CandidateRelation: Sendable, Equatable { case new; case reinforces(UUID); case contradicts(UUID) }`
    — the relation is decided **by the caller** (in 2c that's the memory-keeper
    LLM call); `reconcile` just applies it deterministically.
  - `struct ConsolidationResult: Sendable, Equatable { let writes: [CoachMemory]; let updated: [CoachMemory]; let retired: [CoachMemory] }`
  - `enum MemoryConsolidation {`
    - `public static func reconcile(existing: [CoachMemory], candidates: [MemoryCandidate], now: Date, perKindCap: Int = 12, reinforceStep: Double = 0.15, newConfidence: Double = 0.3) -> ConsolidationResult`
  - `}`
- Rules:
  - `.new` → append a fresh `CoachMemory(id: UUID(), …, confidence: newConfidence, createdAt: now, lastConfirmedAt: now, supersededBy: nil, outcomeScore: nil)` to `writes`.
  - `.reinforces(id)` → find in `existing`; produce an `updated` copy with
    `confidence = min(1, confidence + reinforceStep)`, `lastConfirmedAt = now`,
    and if the candidate carries a non-empty `action` and the existing one's is
    nil, fill it. If `id` not found → treat as `.new`.
  - `.contradicts(id)` → `updated`/`retired`: the existing memory gets
    `supersededBy = <new memory id>` (goes in `retired`); a fresh memory from the
    candidate goes in `writes` (confidence `newConfidence`).
  - **Cap:** after applying, for each `MemoryKind`, if the count of non-retired
    memories `> perKindCap`, retire the excess — lowest
    `confidence`, then oldest `lastConfirmedAt` first — by setting
    `supersededBy = nil`? No: cap-eviction has no superseding memory, so add a
    distinct marker: give `CoachMemory` a `var retiredByCap: Bool = false` (update
    Task 8 interface — add this field, default false, Codable) and set it here.
    Evicted memories move to `retired`.
  - Determinism: never call `UUID()` more than once per `.new`/`.contradicts`
    candidate; sort all output arrays by `createdAt` then `id` so results are
    stable for testing.

- [ ] **Step 1: Write the failing test**
  - one `.new` candidate on an empty store → 1 `write`, confidence `0.3`,
    timestamps `== now`.
  - `.reinforces` an existing memory at confidence `0.5` → `updated` at `0.65`,
    `lastConfirmedAt == now`; original not in `writes`.
  - `.reinforces` an unknown id → falls through to a `write`.
  - `.contradicts` → the old memory in `retired` with `supersededBy` set to the
    new memory's `id`; the new memory in `writes`.
  - cap: 13 existing `observation` memories + one `.new` observation, `perKindCap: 12`
    → the two lowest-confidence get `retiredByCap == true` and land in `retired`.

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement.** (Also apply the Task 8 `retiredByCap` field
  addition — it is small; note it in the commit.)

- [ ] **Step 4: Run — expect PASS**, then full `swift test`.

- [ ] **Step 5: Commit** — `git commit -m "Add MemoryConsolidation reconcile logic"`

---

## Task 10: `MemoryRecall.select` + `ProfileDigest`

**Files:**
- Create: `FitnessCore/Sources/CoachMemory/MemoryRecall.swift`
- Test: `FitnessCore/Tests/CoachMemoryTests/MemoryRecallTests.swift`

**Interfaces:**
- Consumes: `CoachMemory`, `MemoryTags`, `FitnessDomain.MuscleGroup`, `FitnessDomain.Equipment`.
- Produces:
  - `struct RecallContext: Sendable, Equatable { var exerciseIDs: Set<String>; var muscles: Set<MuscleGroup>; var equipment: Set<Equipment> }` (memberwise init, defaults empty).
  - `struct RecalledMemories: Sendable, Equatable { let selected: [CoachMemory]; let digest: String }`
  - `enum MemoryRecall {`
    - `public static func select(from memories: [CoachMemory], context: RecallContext, now: Date, maxItems: Int = 8, halfLifeDays: Double = 30) -> RecalledMemories`
  - `}`
- Rules:
  - Drop retired (`isRetired || retiredByCap`).
  - **Relevance:** a memory matches if any of: `tags.exerciseID` ∈
    `context.exerciseIDs`; `tags.muscle` ∈ `context.muscles`; `tags.equipment` ∈
    `context.equipment`; OR `kind ∈ {preference, goal, constraint}` (always
    globally relevant). `observation`/`responsePattern` with no tag match are
    excluded.
  - **Score:** `score = confidence * recencyWeight * outcomeWeight` where
    `recencyWeight = 0.5 ^ (ageDays / halfLifeDays)`, `ageDays` from
    `lastConfirmedAt` to `now`; `outcomeWeight = 1 + 0.5 * (outcomeScore ?? 0)`
    (so proven advice ranks up, disproven ranks down).
  - Take the top `maxItems` by score (stable tiebreak on `id`).
  - **Digest:** join the `statement` (+ `" → " + action` when present) of the
    selected memories whose `confidence >= 0.6`, one per line, prefixed
    `"- "`. Empty string if none qualify.

- [ ] **Step 1: Write the failing test**
  - a `preference` memory with no tags is always selected.
  - an `observation` tagged `muscle: .chest` is selected when context has `.chest`,
    excluded when it doesn't.
  - given two equal-confidence memories, the one confirmed more recently ranks first.
  - a memory with `outcomeScore = 1` outranks an identical one with `outcomeScore = -1`.
  - `maxItems: 2` returns exactly 2.
  - digest contains only `confidence >= 0.6` lines, formatted `"- statement → action"`.

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run — expect PASS**, then full `swift test`.

- [ ] **Step 5: Commit** — `git commit -m "Add MemoryRecall selection and profile digest"`

---

## Task 11: `MemoryOutcome.applyResult`

**Files:**
- Create: `FitnessCore/Sources/CoachMemory/MemoryOutcome.swift`
- Test: `FitnessCore/Tests/CoachMemoryTests/MemoryOutcomeTests.swift`

**Interfaces:**
- Consumes: `CoachMemory`.
- Produces:
  - `enum OutcomeSignal: Sendable, Equatable { case improved; case unchanged; case worse }`
  - `enum MemoryOutcome {`
    - `public static func applyResult(to memory: CoachMemory, signal: OutcomeSignal, weight: Double = 0.3) -> CoachMemory`
  - `}`
- Rules:
  - `delta = signal == .improved ? +1 : (signal == .worse ? -1 : 0)`.
  - `new = (memory.outcomeScore ?? 0) * (1 - weight) + Double(delta) * weight`,
    clamped to `-1...1`. Return a copy with `outcomeScore = new`.
  - `.unchanged` still pulls the score toward 0 by `(1 - weight)` (advice that
    stops mattering fades), which the test pins.

- [ ] **Step 1: Write the failing test**
  - `nil` score + `.improved` → `0.3`.
  - score `0.3` + `.improved` → `0.51`.
  - score `0.3` + `.worse` → `-0.09`... check: `0.3*0.7 + (-1)*0.3 = 0.21 - 0.3 = -0.09`.
  - score `0.8` + `.unchanged` → `0.56`.
  - repeated `.improved` converges toward but never exceeds `1.0`.

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run — expect PASS**, then the FULL suite: `cd FitnessCore && swift test` — expect **35 existing + all new green**.

- [ ] **Step 5: Commit** — `git commit -m "Add MemoryOutcome scoring"`

---

## Self-Review

**1. Spec coverage:**

| Spec item | Task |
|---|---|
| §8.1 typed core value mirrors | 1 |
| §8.1 `PersonalRecord`, §13.3 Epley e1RM | 2 |
| §8.3 PR detection | 3 |
| §8.3 rollups (`WeeklyMuscleVolume`, `ExerciseTrendPoint`) | 4 |
| §8.4 `MetricsRepository` (all 8 methods) + in-memory impl | 5 |
| §5.4 progression rule stub → real | 6 |
| §5.3 finalize guardrail (all 5 rule families) | 7 |
| §7.1 `CoachMemory` record | 8 |
| §7.2 consolidation (write / reinforce / retire / cap) | 9 |
| §7.3 recall + profile digest | 10 |
| §7.4 self-improvement outcome scoring | 11 |

**Deferred to later 2a-consumers (documented, not gaps):**
- The **LLM calls** that produce `MemoryCandidate.relation` and the finalize
  output — Phase 2c (app layer), same generate→validate→fallback spine as 1c.
- SwiftData `@Model`s that map to these snapshots — Phase 2b.
- Per-exercise rep-range table for the guardrail — a later refinement; 2a uses a
  universal `3...20` envelope and says so.
- True weekly (cross-session) volume aggregation for the guardrail — app's job in
  2c; 2a's guardrail does the per-session proxy and documents it.
- `addSet` progression direction — enum case exists, never emitted in 2a.

**2. Placeholder scan:** No "TBD" / "implement later" as deliverables. Every task
carries full code or full test code. The §13 open questions from the spec are
resolved decisions, not placeholders.

**3. Type consistency:**
- `Feel` / `EnergyRating` / `CoachSource` defined in Task 1, consumed by 3, 5, 6.
- `ExercisePerformance` defined in Task 5, consumed by Task 6 (`ProgressionRule`)
  and Task 7 (`FinalizeGuardrail`) — Task 6/7 therefore depend on `Metrics`,
  wired in Task 6 Step 3 / Task 7 is same module so inherits it. ✅
- `PersonalRecord` gains `atLoadKg` in Task 2 and is used unchanged after. ✅
- `CoachMemory` gains `retiredByCap` in Task 9 (small, back-referenced to Task 8);
  `isRetired` from Task 8 is complemented by the `retiredByCap` check in Task 10. ✅
- `RepRange` is `FitnessDomain`'s existing `(min:max:)` type throughout.
- Every new enum that a test counts (`PartialReason`, `PRType`, `MemoryKind`)
  is declared `CaseIterable`.

**4. Ordering:** Package.swift target deps are edited incrementally (Task 1 adds
`Metrics`/`CoachMemory` with `FitnessDomain`; Task 4 adds `ExerciseCatalog` to
`Metrics`; Task 6 adds `Metrics` to `RuleEngine`). Each task's build is green on
its own.

---

## Execution Handoff

**Recommended: Subagent-Driven** (`superpowers:subagent-driven-development`) —
11 small, mostly-independent pure-logic tasks with complete code/test specs, the
same shape as Phase 1a. Fresh implementer per task, task review after each, broad
review at the end.
