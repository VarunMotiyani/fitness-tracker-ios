# Phase 2b — Persistence & Session Runner — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Phase 2a's pure `Metrics`/`CoachMemory` engine into a working, offline
session-logging experience in the `FitnessTracker` app — SwiftData persistence for
everything the coach records, plus the guided-flexible session runner (Start →
Focus → SessionList → RestTimer → Summary), all driven by the rule engine (no AI
call yet — that is Phase 2c).

**Architecture:** SwiftData `@Model` classes hold the data; a thin mapping layer
converts each `@Model` to/from the matching Phase 2a value snapshot (the
`UserProfile` → `UserContext` pattern from Phase 1). `SwiftDataMetricsRepository`
implements the Phase 2a `MetricsRepository` protocol by fetching models and
handing snapshots to the already-tested `RollupComputer` / `PRDetector` /
`Estimated1RM`. A `@MainActor @Observable SessionRunner` owns the session
lifecycle state machine and persists on every mutation. The SwiftUI screens are
thin over `SessionRunner`.

**Tech Stack:** Swift 6 `.v6`, Xcode 26, iOS 26, SwiftData, SwiftUI, Swift
Testing (`import Testing`) + XCTest UI, `FitnessCore` local package
(`Metrics`, `CoachMemory`, `RuleEngine`, `FitnessDomain`, `ExerciseCatalog`).

**Spec:** `docs/specs/2026-08-29-phase-2-session-runner-design.md`
(§3 lifecycle, §5.4 rule-engine finalisation, §6 runner UI, §8.1 typed core, §14
2b bullet). Also **read `docs/plans/2026-08-29-phase-2a-followups.md`** —
R1 (`supersededBy` may resolve to nothing) and the `MemorySource` wire-format
note bind Task 3's mapping.

## Global Constraints

- **App target only** (`FitnessTracker/FitnessTracker/**` + tests). `FitnessCore/`
  is NOT modified in this plan — it is a merged dependency.
- Xcode 26 default actor isolation is `@MainActor` for the app module. `@Model`
  classes, `@Observable` stores, SwiftUI views, and their tests are `@MainActor`.
  Pure mapping helpers over `Sendable` value types are `nonisolated`.
- **No AI / no network in this plan.** The session is finalised by the rule
  engine only (`RuleEngine.ProgressionRule` + a local time-trim). Phase 2c adds
  the `finalize` LLM call behind the same seam.
- API keys stay in the Keychain (`KeychainStore`) — not touched here, do not
  regress.
- SwiftData: in-memory `ModelConfiguration(isStoredInMemoryOnly: true)` for every
  test. Schema migration: the app container grows from 4 entities to 12; this is
  a lightweight/automatic migration (new model types, no changed properties on
  existing ones) — no `SchemaMigrationPlan` needed, but the plan must be verified
  to open an existing 4-entity store without data loss.
- Tests: model round-trips + mapping + `SwiftDataMetricsRepository` + the
  `SessionRunner` state machine are unit-tested (Swift Testing, `@MainActor`,
  in-memory container). The SwiftUI screens get a build + a manual simulator
  pass (Varun) — same as Phase 1b.
- Commit messages: plain imperative, no body required, **NO `Co-Authored-By`**.
  Do NOT `git push` (controller/Varun handles branch finish).
- Files auto-join targets via Xcode-16 file-system-synchronized groups — no
  `.pbxproj` editing.

## Phase 2a interfaces this plan consumes (do not modify — from `FitnessCore`)

- `Metrics`: `LoggedSetSnapshot`, `CompletedEntrySnapshot`, `CompletedSessionSnapshot`,
  `BodyweightSnapshot`, `DailyCheckinSnapshot`, `ObservationSnapshot`,
  `PersonalRecord`, `PRType`, `PRDetector.newPRs(in:priorPRs:)`,
  `Estimated1RM.epley(loadKg:reps:)`, `RollupComputer(catalog:)`
  (`weeklyMuscleVolume(from:calendar:)`, `exerciseTrend(from:exerciseID:)`),
  `WeeklyMuscleVolume`, `ExerciseTrendPoint`, `MetricsRepository` (protocol,
  8 methods), `ExercisePerformance`, enums `EnergyRating`/`Feel`/`SessionOutcome`
  (`complete`/`partial`)/`PartialReason`/`EntryState`/`CoachSource`,
  `Calendar.isoUTC`, `LoggedSetSnapshot.isWorkingSet`,
  `CompletedEntrySnapshot.countsTowardMetrics`.
- `CoachMemory`: `CoachMemory`, `MemoryKind`, `MemorySource` (`.agent(String)` /
  `.user`), `MemoryTags`, `CoachMemory.isRetired`, `retiredByCap`.
- `RuleEngine`: `ProgressionRule(maxIncreaseFraction:maxDecreaseFraction:)` +
  `.next(currentTargetLoadKg:currentTargetSets:repRange:mechanic:lastPerformance:) -> ProgressionDecision`
  (`ProgressionDirection` / `ProgressionDecision{direction,targetLoadKg,targetSets,rationale}`).
- `FitnessDomain`: `WeeklyPlan`, `PlannedSession`, `PlannedItem`
  (`exerciseID,targetSets,targetReps:RepRange,targetLoadKg:Double?,restSeconds,coachNote`),
  `MuscleGroup`, `Mechanic`, `RepRange`, `Goal`, `ExperienceLevel`.
- `ExerciseCatalog`: `CatalogStore`, `Exercise` (`id,name,primaryMuscle,equipment,mechanic`).
- App (Phase 1): `UserProfile` (+`makeUserContext()`), `StoredPlan`
  (`decodedPlan() -> WeeklyPlan`), `BundledCatalog.load() -> CatalogStore`,
  `RootView`, `PlanView`.

---

## File Structure

**New `@Model` classes — `FitnessTracker/FitnessTracker/Models/`:**
- `SessionModels.swift` — `CompletedSessionModel`, `CompletedEntryModel`, `LoggedSetModel`.
- `HealthModels.swift` — `BodyweightEntryModel`, `DailyCheckinModel`, `ObservationModel`.
- `PersonalRecordModel.swift`.
- `CoachMemoryModel.swift`.

**Mapping — `FitnessTracker/FitnessTracker/Metrics/`:**
- `ModelSnapshotMapping.swift` — `toSnapshot()` / `init(from:)` for every pair.
- `SwiftDataMetricsRepository.swift` — `MetricsRepository` conformance over a `ModelContext`.

**Session logic — `FitnessTracker/FitnessTracker/Session/`:**
- `SessionFinalizer.swift` — rule-engine finalisation (`PlannedSession` + energy/time + repo → `PlannedSession`).
- `SessionRunner.swift` — `@MainActor @Observable` lifecycle store.

**Views — `FitnessTracker/FitnessTracker/Features/Session/`:**
- `SessionStartView.swift`, `SessionFocusView.swift`, `SessionListView.swift`,
  `RestTimerView.swift`, `SessionSummaryView.swift`, `SessionContainerView.swift`.

**Modified:** `FitnessTrackerApp.swift` (container schema), `PlanView.swift`
(a "Start today's session" entry), `RootView.swift` (present the running session).

**Tests — `FitnessTracker/FitnessTrackerTests/`:** one file per model group, the
mapping, the repository, the finalizer, the runner.

---

## Task 1: Session `@Model`s + container registration

**Files:**
- Create: `FitnessTracker/FitnessTracker/Models/SessionModels.swift`
- Modify: `FitnessTracker/FitnessTracker/FitnessTrackerApp.swift`
- Test: `FitnessTracker/FitnessTrackerTests/SessionModelsTests.swift`

**Interfaces — Produces (`@Model final class`, `@MainActor` by module default):**
- `CompletedSessionModel`
  - `var id: UUID`
  - `var startedAt: Date`
  - `var finishedAt: Date?`               // nil ⇒ session in progress
  - `var weekdayRaw: Int`
  - `var timeOfDayMinutes: Int`
  - `var plannedDurationMin: Int`
  - `var actualDurationMin: Int`
  - `var energyRaw: String`               // `EnergyRating.rawValue`
  - `var timeAvailableMin: Int`
  - `var outcomeRaw: String?`             // `SessionOutcome.rawValue`, nil until finished
  - `var partialReasonRaw: String?`       // `PartialReason.rawValue`
  - `var coachSourceRaw: String`          // `CoachSource.rawValue` — always `"rule"` in 2b
  - `var plannedSessionID: UUID?`
  - `var overallNote: String?`
  - `@Relationship(deleteRule: .cascade, inverse: \CompletedEntryModel.session) var entries: [CompletedEntryModel]`
  - `init(id: UUID = UUID(), startedAt: Date, weekdayRaw: Int, timeOfDayMinutes: Int, plannedDurationMin: Int, energyRaw: String, timeAvailableMin: Int, plannedSessionID: UUID?)` — sets `finishedAt = nil`, `actualDurationMin = 0`, `outcomeRaw = nil`, `partialReasonRaw = nil`, `coachSourceRaw = "rule"`, `overallNote = nil`, `entries = []`.
- `CompletedEntryModel`
  - `var exerciseID: String`
  - `var performedOrder: Int`
  - `var stateRaw: String`                // `EntryState.rawValue`
  - `var skipped: Bool`
  - `var wasSwappedFrom: String?`         // always nil in 2b
  - `var feelRaw: String?`                // `Feel.rawValue`
  - `var note: String?`
  - `var session: CompletedSessionModel?`
  - `@Relationship(deleteRule: .cascade, inverse: \LoggedSetModel.entry) var sets: [LoggedSetModel]`
  - `init(exerciseID: String, performedOrder: Int)` — `stateRaw = EntryState.notStarted.rawValue`, `skipped = false`, others nil/empty.
- `LoggedSetModel`
  - `var targetReps: Int`
  - `var targetLoadKg: Double?`
  - `var actualReps: Int`
  - `var actualLoadKg: Double`
  - `var startedAt: Date`
  - `var completedAt: Date`
  - `var restBeforeSec: Int`
  - `var rpe: Double?`
  - `var isWarmup: Bool`
  - `var isDropSet: Bool`
  - `var toFailure: Bool`
  - `var assisted: Bool`
  - `var entry: CompletedEntryModel?`
  - `init(targetReps: Int, targetLoadKg: Double?, actualReps: Int, actualLoadKg: Double, startedAt: Date, completedAt: Date, restBeforeSec: Int)` — flags default `false`, `rpe = nil`.

- [ ] **Step 1: Write the failing test** — `SessionModelsTests.swift`

```swift
import Testing
import SwiftData
import Foundation
@testable import FitnessTracker

@MainActor
@Suite struct SessionModelsTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: CompletedSessionModel.self, CompletedEntryModel.self, LoggedSetModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func sessionWithEntriesAndSetsRoundTrips() throws {
        let ctx = ModelContext(try container())
        let s = CompletedSessionModel(startedAt: .init(timeIntervalSince1970: 0), weekdayRaw: 2,
            timeOfDayMinutes: 1080, plannedDurationMin: 60, energyRaw: "normal",
            timeAvailableMin: 60, plannedSessionID: nil)
        let e = CompletedEntryModel(exerciseID: "bench", performedOrder: 0)
        let set = LoggedSetModel(targetReps: 8, targetLoadKg: 60, actualReps: 8, actualLoadKg: 60,
            startedAt: .init(timeIntervalSince1970: 0), completedAt: .init(timeIntervalSince1970: 40),
            restBeforeSec: 120)
        e.sets.append(set); s.entries.append(e)
        ctx.insert(s)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<CompletedSessionModel>())
        #expect(fetched.count == 1)
        #expect(fetched[0].entries.first?.sets.first?.actualReps == 8)
        #expect(fetched[0].finishedAt == nil)
    }

    @Test func cascadeDeleteRemovesEntriesAndSets() throws {
        let ctx = ModelContext(try container())
        let s = CompletedSessionModel(startedAt: .now, weekdayRaw: 1, timeOfDayMinutes: 600,
            plannedDurationMin: 45, energyRaw: "beat", timeAvailableMin: 45, plannedSessionID: nil)
        let e = CompletedEntryModel(exerciseID: "squat", performedOrder: 0)
        e.sets.append(LoggedSetModel(targetReps: 5, targetLoadKg: 100, actualReps: 5,
            actualLoadKg: 100, startedAt: .now, completedAt: .now, restBeforeSec: 180))
        s.entries.append(e)
        ctx.insert(s); try ctx.save()
        ctx.delete(s); try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<LoggedSetModel>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<CompletedEntryModel>()).isEmpty)
    }
}
```

- [ ] **Step 2: Run — expect FAIL** (`xcodebuild test` with `-only-testing:FitnessTrackerTests/SessionModelsTests`) — types don't exist.

- [ ] **Step 3: Implement `SessionModels.swift`** with the three `@Model` classes above. Use `@Relationship(deleteRule: .cascade, inverse:)` exactly as specified so deleting a session removes its entries and sets.

- [ ] **Step 4: Register in the container** — `FitnessTrackerApp.swift`:
```swift
.modelContainer(for: [
    UserProfile.self, StoredPlan.self, ProviderProfile.self, AICallRecord.self,
    CompletedSessionModel.self, CompletedEntryModel.self, LoggedSetModel.self,
])
```
(Tasks 2–4 add the remaining five.)

- [ ] **Step 5: Run tests — expect PASS.** Then the full app suite (`xcodebuild test -scheme FitnessTracker -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A'`) — existing 38 + 2 new, green, and confirm the app still builds.

- [ ] **Step 6: Commit** — `git commit -m "Add session SwiftData models"`

---

## Task 2: Health + PR + memory `@Model`s

**Files:**
- Create: `FitnessTracker/FitnessTracker/Models/HealthModels.swift`,
  `FitnessTracker/FitnessTracker/Models/PersonalRecordModel.swift`,
  `FitnessTracker/FitnessTracker/Models/CoachMemoryModel.swift`
- Modify: `FitnessTracker/FitnessTracker/FitnessTrackerApp.swift`
- Test: `FitnessTracker/FitnessTrackerTests/HealthAndMemoryModelsTests.swift`

**Interfaces — Produces (`@Model final class`):**
- `BodyweightEntryModel { var date: Date; var kg: Double; init(date:kg:) }`
- `DailyCheckinModel { var date: Date; var sleepQuality: Int?; var soreness: Int?; var note: String?; init(date:) }`
- `ObservationModel { var kind: String; var value: Double; var unit: String; var timestamp: Date; var contextJSON: String; var sessionID: UUID?; var entryExerciseID: String?; init(kind:value:unit:timestamp:) }`
  — `contextJSON` holds the `[String:String]` context encoded as a JSON object string, default `"{}"`.
- `PersonalRecordModel { var typeRaw: String; var exerciseID: String; var value: Double; var atLoadKg: Double; var reps: Int; var date: Date; var sessionID: UUID; init(typeRaw:exerciseID:value:atLoadKg:reps:date:sessionID:) }`
- `CoachMemoryModel`
  - `var id: UUID`
  - `var kindRaw: String`               // `MemoryKind.rawValue`
  - `var statement: String`
  - `var action: String?`
  - `var confidence: Double`
  - `var sourceKind: String`            // `"agent"` | `"user"`  — flat, NOT the synthesised enum shape (2a follow-up note)
  - `var sourceAgent: String?`          // set when `sourceKind == "agent"`
  - `var createdAt: Date`
  - `var lastConfirmedAt: Date`
  - `var supersededBy: UUID?`
  - `var retiredByCap: Bool`
  - `var outcomeScore: Double?`
  - `var tagExerciseID: String?`
  - `var tagMuscleRaw: String?`
  - `var tagEquipmentRaw: String?`
  - `var tagFreeJSON: String`           // `[String]` as JSON array string, default `"[]"`
  - `init(id: UUID = UUID(), kindRaw: String, statement: String, confidence: Double, sourceKind: String, createdAt: Date, lastConfirmedAt: Date)` — `action = nil`, `sourceAgent = nil`, `supersededBy = nil`, `retiredByCap = false`, `outcomeScore = nil`, tag* nil, `tagFreeJSON = "[]"`.

- [ ] **Step 1: Write the failing test** — an in-memory container over all five new
  types; for each: construct, insert, save, fetch, assert a representative field
  survives; for `CoachMemoryModel` assert `sourceKind`/`sourceAgent` store a flat
  `("agent", "memoryKeeper")` and `supersededBy` round-trips a `UUID?`.

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement the three files.**

- [ ] **Step 4: Add all five to the container** in `FitnessTrackerApp.swift` (final
  list = 12 entities).

- [ ] **Step 5: Run tests — expect PASS**; full app suite green; app builds.

- [ ] **Step 6: Commit** — `git commit -m "Add health, PR, and coach-memory SwiftData models"`

---

## Task 3: Model ↔ Phase-2a-snapshot mapping

**Files:**
- Create: `FitnessTracker/FitnessTracker/Metrics/ModelSnapshotMapping.swift`
- Test: `FitnessTracker/FitnessTrackerTests/ModelSnapshotMappingTests.swift`

**Interfaces — Produces:**
- `extension LoggedSetModel { func toSnapshot() -> LoggedSetSnapshot }`
- `extension CompletedEntryModel { func toSnapshot() -> CompletedEntrySnapshot }`
  — `state` from `EntryState(rawValue: stateRaw) ?? .notStarted`; `feel` from
  `feelRaw.flatMap(Feel.init(rawValue:))`; `sets` mapped in stored order.
- `extension CompletedSessionModel { func toSnapshot() -> CompletedSessionSnapshot }`
  — `energy` from `EnergyRating(rawValue: energyRaw) ?? .normal`; `outcome` from
  `outcomeRaw.flatMap(SessionOutcome.init(rawValue:)) ?? .partial` (an unfinished
  session snapshots as `.partial` — callers that care check `finishedAt`);
  `partialReason` from `partialReasonRaw.flatMap(PartialReason.init(rawValue:))`;
  `coachSource` from `CoachSource(rawValue: coachSourceRaw) ?? .rule`; `weekday`
  from `weekdayRaw`.
- `extension BodyweightEntryModel { func toSnapshot() -> BodyweightSnapshot }`
- `extension DailyCheckinModel { func toSnapshot() -> DailyCheckinSnapshot }`
- `extension ObservationModel { func toSnapshot() -> ObservationSnapshot }`
  — decode `contextJSON` to `[String:String]` (`[:]` on failure).
- `extension PersonalRecordModel { func toSnapshot() -> PersonalRecord }`
  — `type` from `PRType(rawValue: typeRaw) ?? .heaviestWeight`.
- `func personalRecordModel(from pr: PersonalRecord) -> PersonalRecordModel`
- `extension CoachMemoryModel { func toDomain() -> CoachMemory }`
  — `source`: `sourceKind == "user" ? .user : .agent(sourceAgent ?? "unknown")`;
  `tags` rebuilt from the tag* columns (`tagFreeJSON` decoded to `[String]`, `[]`
  on failure); `kind` from `MemoryKind(rawValue: kindRaw) ?? .observation`.
  **`supersededBy` is carried through verbatim even if it resolves to no row**
  (Phase 2a follow-up R1 — a dangling id is valid and means "retired, successor
  not recorded").
- `func coachMemoryModel(from m: CoachMemory) -> CoachMemoryModel` — inverse;
  `MemorySource` → `sourceKind`/`sourceAgent` flat columns.
- All mapping funcs are `nonisolated` where they only touch `Sendable`
  snapshot/value types and plain stored properties. (Reading a `@Model`'s stored
  properties is main-actor; these run from `@MainActor` call sites, so mark the
  `@Model` extensions `@MainActor` if the compiler requires — do NOT add
  `nonisolated` to something that reads a `@Model`.)

- [ ] **Step 1: Write the failing test** — for each pair, build the `@Model`,
  `toSnapshot()`, assert every field maps (spot every enum + the JSON-encoded
  ones); for `PersonalRecord` and `CoachMemory` also assert the value→model→value
  round-trip is lossless; assert a `CoachMemoryModel` with `supersededBy` set to a
  random UUID (no matching row) still yields `isRetired == true` on `toDomain()`.

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run tests — expect PASS**; full app suite green.

- [ ] **Step 5: Commit** — `git commit -m "Map SwiftData models to and from FitnessCore snapshots"`

---

## Task 4: `SwiftDataMetricsRepository`

**Files:**
- Create: `FitnessTracker/FitnessTracker/Metrics/SwiftDataMetricsRepository.swift`
- Test: `FitnessTracker/FitnessTrackerTests/SwiftDataMetricsRepositoryTests.swift`

**Interfaces — Produces:**
- `@MainActor struct SwiftDataMetricsRepository: MetricsRepository`
  - `init(context: ModelContext, catalog: CatalogStore, plannedSessionsPerWeek: Int, now: @escaping () -> Date = { .now }, calendar: Calendar = .isoUTC)`
  - Implements all 8 `MetricsRepository` methods. Because the protocol methods are
    `nonisolated` in `FitnessCore` but this impl touches `ModelContext`, the
    conformance is `@MainActor` — that is allowed (a `@MainActor` type may satisfy
    a `nonisolated` protocol requirement from `@MainActor` call sites; if the
    compiler rejects a specific signature, wrap the body in
    `MainActor.assumeIsolated` and document why).
  - Strategy: fetch only **finished** `CompletedSessionModel`s
    (`finishedAt != nil`), `.toSnapshot()` them, and delegate to the Phase 2a
    pure code:
    - `lastPerformance` / `bestSet` / `e1RMSeries` / `weeklyVolume` / `stalls` →
      build the `[CompletedSessionSnapshot]` list, hand to `RollupComputer` /
      the same logic `InMemoryMetricsRepository` uses. **Do not re-implement the
      algorithms — reuse `InMemoryMetricsRepository` by constructing it from the
      fetched snapshots** (it takes `sessions:priorPRs:observations:plannedSessionsPerWeek:catalog:calendar:`).
      i.e. `SwiftDataMetricsRepository` is a thin adapter that fetches + forwards.
    - `personalRecords` → fetch `PersonalRecordModel`s, `.toSnapshot()`, filter by
      `exerciseID` if given.
    - `observations` → fetch `ObservationModel`s, map, filter by `kind` + `since`.
  - `adherence(weeks:now:)` — forwarded to the inner `InMemoryMetricsRepository`
    built with `plannedSessionsPerWeek`.

- [ ] **Step 1: Write the failing test** — an in-memory container seeded with ~3
  finished sessions (+ 1 unfinished, which must be ignored) across 2 ISO weeks, a
  couple `PersonalRecordModel`s, one `ObservationModel`. A tiny 2-exercise
  `CatalogStore`. Assert each of the 8 methods returns the same values a directly-
  constructed `InMemoryMetricsRepository` over the equivalent snapshots returns
  (parity test), and that the unfinished session contributes nothing.

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement** as the thin fetch-and-forward adapter.

- [ ] **Step 4: Run tests — expect PASS**; full app suite green.

- [ ] **Step 5: Commit** — `git commit -m "Add SwiftData-backed MetricsRepository"`

---

## Task 5: `SessionFinalizer` (rule engine only)

**Files:**
- Create: `FitnessTracker/FitnessTracker/Session/SessionFinalizer.swift`
- Test: `FitnessTracker/FitnessTrackerTests/SessionFinalizerTests.swift`

**Interfaces — Produces:**
- `nonisolated struct FinalizedSession: Sendable { let session: PlannedSession; let perItemRationale: [String: String] }`
- `@MainActor struct SessionFinalizer`
  - `init(catalog: CatalogStore, repository: any MetricsRepository)`
  - `func finalize(_ planned: PlannedSession, energy: EnergyRating, timeAvailableMin: Int) -> FinalizedSession`
  - Behaviour (rule-engine finalisation, spec §5.4):
    1. For each `PlannedItem`: look up the exercise's `mechanic` via `catalog`;
       `repository.lastPerformance(exerciseID:)` → `ProgressionRule().next(currentTargetLoadKg: item.targetLoadKg ?? 0, currentTargetSets: item.targetSets, repRange: item.targetReps, mechanic: mechanic, lastPerformance: lastPerf)`.
       Rebuild the item with `targetLoadKg = decision.targetLoadKg` (keep `nil`
       only if the decision load is `0` **and** there was no history), `targetSets = decision.targetSets`.
       Record `decision.rationale` in `perItemRationale[item.exerciseID]`.
    2. **Energy trim:** `energy == .beat` → drop the single lowest-priority
       accessory (last isolation item in `items`); `energy == .great` → no change;
       `.normal` → no change.
    3. **Time trim:** estimate `Σ targetSets * (40 + restSeconds) / 60` minutes;
       while `> timeAvailableMin` and `items.count > 1`, drop the last item.
    4. Return the rebuilt `PlannedSession` (same `id`, `order`, `focusMuscles`)
       + the rationale map.
  - No AI, no network. Deterministic.

- [ ] **Step 1: Write the failing test** — a `CatalogStore` with a compound
  (`bench`, `.compound`) and an isolation (`fly`, `.isolation`); a stub
  `MetricsRepository` (reuse `InMemoryMetricsRepository` seeded with a prior
  bench session at `3×8 @ 60`, feel `.easy`, all reps hit). Assert:
  - bench `targetLoadKg` moves up (progression applied), rationale non-empty.
  - `energy: .beat` drops the isolation item.
  - a `timeAvailableMin` far below the estimate trims trailing items to fit.
  - `energy: .normal`, generous time → item count unchanged, only loads/sets updated.

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run tests — expect PASS**; full app suite green.

- [ ] **Step 5: Commit** — `git commit -m "Add rule-engine SessionFinalizer"`

---

## Task 6: `SessionRunner` — the lifecycle store

**Files:**
- Create: `FitnessTracker/FitnessTracker/Session/SessionRunner.swift`
- Test: `FitnessTracker/FitnessTrackerTests/SessionRunnerTests.swift`

**Interfaces — Produces:**
- `@MainActor @Observable final class SessionRunner`
  - `enum Phase: Equatable { case idle, finalizing, active, summary, finished(SessionOutcome) }`
  - `private(set) var phase: Phase`
  - `private(set) var session: CompletedSessionModel?` — the persisted row (created at `start`)
  - `private(set) var finalized: FinalizedSession?`
  - `var currentEntryIndex: Int` — drives the Focus view; free to set to any valid index (jump-around)
  - `init(modelContext: ModelContext, catalog: CatalogStore, repository: any MetricsRepository, finalizer: SessionFinalizer, now: @escaping () -> Date = { .now })`
  - `func start(planned: PlannedSession, energy: EnergyRating, timeAvailableMin: Int)` —
    phase `.finalizing` → run `finalizer.finalize(...)` → create+insert a
    `CompletedSessionModel` (`startedAt = now()`, `weekdayRaw`/`timeOfDayMinutes`
    from `now()` via `Calendar.isoUTC`, `plannedDurationMin` from the finalized
    estimate, `energyRaw`, `timeAvailableMin`, `plannedSessionID = planned.id`),
    one `CompletedEntryModel` per finalized item (`performedOrder` = index,
    `stateRaw = .notStarted`), `save()`, phase `.active`.
  - `func logSet(entryIndex: Int, actualReps: Int, actualLoadKg: Double, restBeforeSec: Int, flags: SetFlags = .init())` —
    append a `LoggedSetModel` to that entry, set the entry `stateRaw = .inProgress`,
    `save()`. `SetFlags` = `{ isWarmup, isDropSet, toFailure, assisted }` all default `false`.
  - `func markDone(entryIndex: Int)` / `func markSkipped(entryIndex: Int)` —
    set `stateRaw = .done`; `skipped` on the skip path; `save()`.
  - `func reorder(from: Int, to: Int)` — reassign `performedOrder` across entries; `save()`.
  - `func setFeel(entryIndex: Int, _ feel: Feel)` / `func setEntryNote(entryIndex: Int, _ text: String)` — `save()`.
  - `func finish(partialReason: PartialReason?, overallNote: String?)` —
    compute `outcome`: `.complete` iff every entry `stateRaw == .done`, else
    `.partial`; set `finishedAt = now()`, `actualDurationMin` from
    `now() - startedAt`, `outcomeRaw`, `partialReasonRaw`, `overallNote`; `save()`.
    Then **PR detection:** build the session snapshot, fetch all
    `PersonalRecordModel` → snapshots, `PRDetector().newPRs(in:priorPRs:)`,
    persist each new one as a `PersonalRecordModel`; `save()`. Expose the new PRs
    via `private(set) var lastSessionPRs: [PersonalRecord]`. Phase `.summary`,
    then `.finished(outcome)` when the summary is dismissed (`func closeSummary()`).
  - `static func resolveAbandoned(in context: ModelContext, now: Date, staleAfter: TimeInterval = 4 * 3600)` —
    for every `CompletedSessionModel` with `finishedAt == nil` and
    `now - startedAt > staleAfter`: set `finishedAt = startedAt` (best guess),
    `outcomeRaw = SessionOutcome.partial.rawValue`, `partialReasonRaw = nil`;
    run the same PR detection; `save()`. Called once from `RootView.task`.

- [ ] **Step 1: Write the failing test** — in-memory container + a 2-item
  `PlannedSession` + a stub repo/finalizer. Drive the state machine:
  - `start(...)` → `phase == .active`, one `CompletedSessionModel` persisted with
    2 `notStarted` entries, `finishedAt == nil`.
  - `logSet(entryIndex: 0, …)` twice → entry 0 has 2 `LoggedSetModel`s,
    `stateRaw == .inProgress`.
  - `markDone(0)`, `markDone(1)` → `finish(partialReason: nil, …)` →
    `outcome == .complete`, `finishedAt != nil`, `actualDurationMin >= 0`.
  - a run where only entry 0 is `.done` → `finish(...)` → `outcome == .partial`,
    `partialReasonRaw` stored.
  - a `logSet` that sets an all-time-heaviest load → after `finish`, a
    `PersonalRecordModel` exists and `lastSessionPRs` is non-empty.
  - `resolveAbandoned` on a container with one 5-hour-old unfinished session →
    it becomes `.partial`, `finishedAt == startedAt`.

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run tests — expect PASS**; full app suite green.

- [ ] **Step 5: Commit** — `git commit -m "Add SessionRunner lifecycle store"`

---

## Task 7: `SessionStartView` + `SessionContainerView`

> **View task — bounces to Varun for the build + simulator check.** The
> implementer writes the SwiftUI, self-reviews the code, commits; Varun runs
> `⌘R` and confirms the screen. Acceptance = builds + the screen renders + the
> energy/time selection feeds `SessionRunner.start`.

**Files:**
- Create: `FitnessTracker/FitnessTracker/Features/Session/SessionStartView.swift`,
  `FitnessTracker/FitnessTracker/Features/Session/SessionContainerView.swift`

**Interfaces:**
- `SessionContainerView(planned: PlannedSession, catalog: CatalogStore)` — owns a
  `@State private var runner: SessionRunner` (built in `.task` from
  `@Environment(\.modelContext)` + a `SwiftDataMetricsRepository` + a
  `SessionFinalizer`; `plannedSessionsPerWeek` from the single `UserProfile`).
  Switches on `runner.phase`: `.idle` → `SessionStartView`; `.finalizing` →
  a skeleton/`ProgressView`; `.active` → `SessionFocusView` (Task 8) with the
  `SessionListView` pull-tab (Task 9); `.summary` → `SessionSummaryView` (Task 11);
  `.finished` → dismiss (call an `onFinished` closure the caller passes).
- `SessionStartView(planned: PlannedSession, catalog: CatalogStore, onStart: (EnergyRating, Int) -> Void)` —
  session name (`"Session \(order+1)"` + focus muscles), exercise count, estimated
  time; energy as 3 large buttons (`beat` / `normal` / `great`); time as chips
  (45 / 60 / 90 / custom stepper); "Start" calls `onStart`.

- [ ] **Step 1: Write both views.** No unit test (pure SwiftUI); a `#Preview` for
  `SessionStartView` with a stub `PlannedSession`.
- [ ] **Step 2: Build** (`xcodebuild build …`). Fix compile errors.
- [ ] **Step 3: Commit** — `git commit -m "Add session start screen and container"`
- [ ] **Step 4: Hand to Varun** — "run the app, get to a plan, note there's no
  entry point yet (Task 12 wires it); for now verify `SessionStartView` via the
  Xcode preview."

---

## Task 8: `SessionFocusView` + set logging

> **View task — bounces to Varun.**

**Files:**
- Create: `FitnessTracker/FitnessTracker/Features/Session/SessionFocusView.swift`

**Interfaces:**
- `SessionFocusView(runner: SessionRunner, catalog: CatalogStore)` — renders
  `runner.finalized?.session.items[runner.currentEntryIndex]`:
  - exercise name + `catalog.exercise(id:)?.instructions` first cue + image
    (`imagePaths` — may be empty; show a placeholder).
  - the target line (`sets × repRange @ load`), the per-item rationale from
    `runner.finalized?.perItemRationale` shown behind a "why?" disclosure.
  - a set list: one row per already-logged `LoggedSetModel` for this entry
    (from `runner.session?.entries`), then a "log next set" row pre-filled with
    the target — `Stepper` for reps, `Stepper`/`TextField` for load (2.5 kg
    steps), a warm-up toggle, "Log set" → `runner.logSet(...)`.
  - a "Done" button → `runner.markDone(currentEntryIndex)`; auto-suggests Done
    (highlighted) once the logged set count reaches `targetSets`.
  - "Next" / "Previous" advance `runner.currentEntryIndex` within bounds; a
    toolbar button opens `SessionListView` (Task 9) as a sheet.

- [ ] **Step 1: Write the view** + a `#Preview` with a stub runner.
- [ ] **Step 2: Build.** Fix errors.
- [ ] **Step 3: Commit** — `git commit -m "Add session focus screen with set logging"`
- [ ] **Step 4: Hand to Varun.**

---

## Task 9: `SessionListView` — jump-around / reorder / skip

> **View task — bounces to Varun.**

**Files:**
- Create: `FitnessTracker/FitnessTracker/Features/Session/SessionListView.swift`

**Interfaces:**
- `SessionListView(runner: SessionRunner, catalog: CatalogStore)` — a `List` of
  every finalized item with a state dot (`notStarted` grey / `inProgress` amber /
  `done` green, from the matching `CompletedEntryModel.stateRaw`); tap a row →
  set `runner.currentEntryIndex` and dismiss; `.onMove` → `runner.reorder(from:to:)`;
  swipe → "Skip" → `runner.markSkipped(index)`. A "Finish session" button pinned
  at the bottom → calls an `onFinish` closure (the container routes it to the
  summary; if not all entries are `.done` it first shows a one-tap
  "N of M done — finish as partial?" confirmation).

- [ ] **Step 1: Write the view** + `#Preview`.
- [ ] **Step 2: Build.** Fix errors.
- [ ] **Step 3: Commit** — `git commit -m "Add session list with reorder, skip, finish"`
- [ ] **Step 4: Hand to Varun.**

---

## Task 10: `RestTimerView`

> **View task — bounces to Varun.** Timing behaviour is manual-verify only.

**Files:**
- Create: `FitnessTracker/FitnessTracker/Features/Session/RestTimerView.swift`

**Interfaces:**
- `@MainActor @Observable final class RestTimer` — `start(seconds: Int)`,
  `add(_ delta: Int)`, `skip()`, `private(set) var remaining: Int`,
  `private(set) var isRunning: Bool`. Drives a 1-second `Timer`/`AsyncTimerSequence`;
  fires a haptic (`UINotificationFeedbackGenerator`) at zero. (A local
  notification when backgrounded is a Phase-4 concern — leave a `// TODO(phase4)`.)
- `RestTimerView(timer: RestTimer)` — a circular countdown; +30s / −30s / skip
  buttons. `SessionFocusView` owns a `RestTimer` and calls `start(seconds:)` with
  the current item's `restSeconds` after each `logSet`.

- [ ] **Step 1: Write the timer + view.** Unit-test `RestTimer` state transitions
  (`start` sets `remaining` + `isRunning`; `add` clamps at 0; `skip` stops) with
  a synchronous tick hook, NOT a real 1s wait.
- [ ] **Step 2: Build + run the RestTimer unit test — green.**
- [ ] **Step 3: Commit** — `git commit -m "Add rest timer"`
- [ ] **Step 4: Hand to Varun** for the visual/haptic check.

---

## Task 11: `SessionSummaryView` + feedback capture

> **View task — bounces to Varun.**

**Files:**
- Create: `FitnessTracker/FitnessTracker/Features/Session/SessionSummaryView.swift`

**Interfaces:**
- `SessionSummaryView(runner: SessionRunner, catalog: CatalogStore, onClose: () -> Void)`:
  - **Volume vs target:** per muscle trained today, sets logged (from the session
    snapshot via `RollupComputer` over just this session) vs the planned
    `targetSets` — a simple list.
  - **PRs:** `runner.lastSessionPRs` — a celebratory row each (`"New bench PR: 62.5 kg"`).
  - **Per-exercise feel:** each entry, 3 buttons (`easy` / `right` / `brutal`) →
    `runner.setFeel(entryIndex:_:)`; optional note field → `runner.setEntryNote`.
  - **If partial:** a "what got in the way?" chip row
    (`ranOutOfTime` / `tooTired` / `painNiggle` / `gymCrowded` / `notFeelingIt` /
    `other`) bound to a `@State partialReason`.
  - Optional overall note.
  - "Save" → `runner.finish(partialReason:overallNote:)` was already called by the
    list's finish action; here "Save" just persists the feedback (`setFeel` /
    `setEntryNote` already saved) and calls `onClose()` → `runner.closeSummary()`.
    _Adjust the ordering so `finish` runs when the user commits the summary, not
    before — the implementer picks whichever is cleaner and notes it._

- [ ] **Step 1: Write the view** + `#Preview`.
- [ ] **Step 2: Build.** Fix errors.
- [ ] **Step 3: Commit** — `git commit -m "Add session summary and feedback capture"`
- [ ] **Step 4: Hand to Varun.**

---

## Task 12: Wire into the app + acceptance + docs

> **Mixed — code is small, then a full Varun simulator pass.**

**Files:**
- Modify: `FitnessTracker/FitnessTracker/Features/Plan/PlanView.swift`,
  `FitnessTracker/FitnessTracker/RootView.swift`
- Modify: `FitnessTracker/README.md`, `docs/HANDOFF.md`,
  `docs/04-roadmap-phases.md`

**Interfaces / behaviour:**
- `PlanView` — for the session whose `order` matches "today" (2b heuristic:
  `order == 0` — a real day-of-week mapping is Phase 3), add a prominent
  **"Start this session"** button that navigates to
  `SessionContainerView(planned: session, catalog: catalog)`.
- `RootView` — present `SessionContainerView` (via `NavigationLink` or
  `.fullScreenCover`); on its `onFinished`, pop back to the plan. Call
  `SessionRunner.resolveAbandoned(in: context, now: .now)` once from `RootView`'s
  existing `.task`.
- **No new AI wiring** — `SessionContainerView` builds its `SessionRunner` with
  the rule-engine `SessionFinalizer`. Phase 2c swaps in the AI path here.

- [ ] **Step 1: Wire `PlanView` + `RootView`.** Build.
- [ ] **Step 2: Full unit suite** — `xcodebuild test` all green;
  `cd FitnessCore && swift test` still 126.
- [ ] **Step 3: Simulator acceptance (Varun).** Clean install →
  onboarding → plan → "Start this session" → pick energy/time → log every set of
  a session → tick each exercise done → Summary shows volume + any PR + feel
  capture → Save. Then: a partial finish (leave one exercise not-done → confirm
  → partial reason). Then: force-quit mid-session, reopen after (simulated) 4h →
  session auto-resolves to partial. Report what each screen showed.
- [ ] **Step 4: Docs** — `FitnessTracker/README.md` gains a "Phase 2b" section
  (session models, `SwiftDataMetricsRepository`, `SessionRunner`, the runner
  screens, rule-engine finalisation, PR detection). `docs/HANDOFF.md` status →
  "Phase 2b merged; next = 2c"; chronology entry; bump date.
  `docs/04-roadmap-phases.md` — mark the 2b slice of Phase 2 done.
- [ ] **Step 5: Commit** — `git commit -m "Wire session runner into the app; Phase 2b acceptance and docs"`

---

## Self-Review

**1. Spec coverage:**

| Spec item | Task |
|---|---|
| §8.1 typed core as SwiftData `@Model`s | 1, 2 |
| §8.2 extensible `Observation` channel | 2 (`ObservationModel`) |
| §7.1 `CoachMemory` persisted (flat `MemorySource`, dangling `supersededBy` ok) | 2, 3 |
| §8.4 `MetricsRepository` over real data | 4 |
| §5.4 rule-engine session finalisation | 5 |
| §3 session lifecycle (Scheduled→Finalizing→Active→Summary→Complete/Partial) | 6 |
| §3 per-exercise done/skip ticks; §3.1 feedback capture | 6, 9, 11 |
| §3 abandon → auto-partial after 4h | 6 (`resolveAbandoned`), 12 |
| §6 Start / Focus / SessionList / RestTimer / Summary screens | 7, 8, 9, 10, 11 |
| §8.3 PR detection on finish | 6 |
| entry point from the plan | 12 |

**Deferred (documented, not gaps):**
- The AI `finalize` / memory-keeper / analyst calls → **Phase 2c** (Task 5's
  `SessionFinalizer` is the seam; `CoachMemoryModel` + its mapping ship here so
  2c only adds the LLM call).
- Persisted rollup caches (`WeeklyMuscleVolume`/`ExerciseTrendPoint` `@Model`s) —
  `SwiftDataMetricsRepository` computes on the fly from session models via the
  pure `RollupComputer`; add caches in 2d only if a profiler says so.
- History views, "what your coach knows" screen, pick-a-split → **Phase 2d**.
- Real day-of-week → session mapping (2b uses `order == 0` for "today") → Phase 3.
- Local notification for the rest timer when backgrounded → Phase 4.
- Phase 2a follow-ups R2–R5 (light-load clamp, cosmetics) → not touched here;
  R1 (dangling `supersededBy`) IS handled in Task 3's mapping.

**2. Placeholder scan:** No "TBD"/"implement later" as deliverables. View tasks
give the full interface + behaviour and the `#Preview`; timing/haptic behaviour
is explicitly manual-verify (matches how Phase 1b handled view tasks).

**3. Type consistency:**
- `@Model` raw-string columns (`energyRaw`, `stateRaw`, `feelRaw`,
  `outcomeRaw`, `partialReasonRaw`, `coachSourceRaw`, `kindRaw`, `typeRaw`) all
  map through the matching Phase 2a `enum(rawValue:)` in Task 3, falling back to
  the safe default named there.
- `SessionFinalizer` consumes `MetricsRepository` (Task 4 provides the real one,
  tests use `InMemoryMetricsRepository`); `SessionRunner` consumes
  `SessionFinalizer` + `MetricsRepository` + `ModelContext`.
- `SwiftDataMetricsRepository` forwards to `InMemoryMetricsRepository` rather than
  re-implementing — one algorithm, already tested in 2a.
- Container entity list grows 4 → 7 (Task 1) → 12 (Task 2) and is never reduced.

**4. Migration:** new `@Model` types only; no property changes to `UserProfile` /
`StoredPlan` / `ProviderProfile` / `AICallRecord`. SwiftData's automatic
lightweight migration covers additive schema changes. Task 1 Step 5 and Task 2
Step 5 both run the full existing suite to confirm the pre-2b store still opens.

---

## Execution Handoff

**Recommended: Subagent-Driven for Tasks 1–6** (model / mapping / repository /
finalizer / runner — pure-ish, fully unit-tested, no UI), then **Tasks 7–12 run
with Varin in the loop** (implementer writes the SwiftUI + `#Preview` + commits;
Varun does `⌘R` / simulator). Task 12's acceptance pass is Varun's.
