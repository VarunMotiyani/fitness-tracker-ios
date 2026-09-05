# Memory-Keeper Call Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first working vertical slice of the memory-keeper call —
the LLM call `MemoryConsolidation.reconcile` has been waiting for since it was
built. After a session finishes, a background call reads the session, today's
check-in, and the live memory set, and proposes memory candidates (fed
through the existing deterministic `reconcile`) and measurement candidates
(guardrail-bounded, landing as unconfirmed `ObservationModel` rows you
approve from a Home card). Never blocks the UI; a skipped/failed call is
always a silent, valid no-op.

**Architecture:** Same provider-agnostic tool-loop pattern as the finalize
call (`ToolLoopRunner`, `ToolLoopTurn`, `ToolRegistry`) — one well-orchestrated
call, `QueryTrainingDataTool` available for the model to pull more history
itself. `MemoryKeeperCoordinator` fires from `SessionRunner.finish()` as a
detached `Task`, decodes a `MemoryKeeperDTO`, and routes its two arrays
through two independent, already-mostly-built deterministic pipelines:
`MemoryConsolidation.reconcile` (memory) and a new `MeasurementGuardrail`
(measurements). The model never writes to SwiftData directly.

**Tech Stack:** Swift 6 `.v6`, Xcode 26, iOS 26, SwiftData, SwiftUI, Swift
Testing (`import Testing`), `FitnessCore` local package (`CoachMemory`,
`Metrics`, `LLMKit`, `FitnessDomain`).

**Spec:** `docs/specs/2026-09-05-memory-keeper-call-design.md` (all sections).
Also read `docs/specs/2026-09-05-ai-coach-layer-v2-design.md` §5 for the
memory layer's existing shape, and
`docs/plans/2026-09-05-ai-coach-orchestrator-core.md` Task 6/7 for the
`FinalizeDTO`/`FinalizePromptBuilder`/`SessionFinalizeCoordinator` patterns
this plan mirrors.

## Global Constraints

- Xcode 26 default actor isolation is `@MainActor` for the app module.
  Coordinators/tools touching `ModelContext` are `@MainActor`. Pure DTO/prompt
  types are `nonisolated`, following `FinalizeDTO`/`FinalizePromptBuilder`.
- **This call never blocks the UI and never has to produce anything.** No
  provider configured, provider throws, tool loop exceeds its cap, or the
  final decode fails → the call is abandoned silently: nothing written, no
  error surfaced, no retry, no `AICallRecord` (nothing to bill). This is
  different from finalize, which must always produce *some* session — memory-
  keeper's valid outcome is often "learned nothing new."
- Every paid provider call that *is* made writes one `AICallRecord`
  (`callType = "memoryKeeper"`), call-granular per tool-loop turn, mirroring
  `SessionFinalizeCoordinator`'s `recordCalls` helper and the
  `ToolLoopResult<Final>`/`CallOutcome` types it already returns.
- No real network in any test — use `StubLLMProvider` (already exists,
  extended for the finalize plan to script a sequence of turns).
- Plain commits, **no `Co-Authored-By` trailer**. Do **not** commit or push
  without being asked first — confirmed standing rule for this project.
- End state: `xcodebuild test -scheme FitnessTracker -destination
  'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' -project
  FitnessTracker/FitnessTracker.xcodeproj 2>&1 | tail -30` green.

---

## File Structure

- `FitnessTracker/FitnessTracker/Models/HealthModels.swift` — add
  `ObservationModel.confirmed: Bool` (Task 1).
- `FitnessTracker/FitnessTracker/Export/HistoryExportManager.swift` — filter
  `confirmed == true` into the export (Task 1).
- `FitnessTracker/FitnessTracker/Metrics/SwiftDataMetricsRepository.swift` —
  filter `confirmed == true` in `observations(kind:since:)` (Task 1).
- `FitnessTracker/FitnessTracker/AI/MeasurementGuardrail.swift` — **create**:
  plausibility bounds per measurement kind (Task 2).
- `FitnessTracker/FitnessTracker/AI/MemoryKeeperDTO.swift` — **create**: the
  model's output shape and its mapping to `MemoryCandidate` (Task 3).
- `FitnessTracker/FitnessTracker/AI/MemoryKeeperPromptBuilder.swift` —
  **create**: system/user prompts (Task 3).
- `FitnessTracker/FitnessTracker/AI/MemoryKeeperCoordinator.swift` —
  **create**: the orchestrator (Task 4).
- `FitnessTracker/FitnessTracker/Session/SessionRunner.swift` — modify:
  optional `memoryKeeper` dependency, fired from `finish()` (Task 5).
- `FitnessTracker/FitnessTracker/Features/Session/SessionContainerView.swift`
  — modify: construct `MemoryKeeperCoordinator` alongside the finalizer
  (Task 5).
- `FitnessTracker/FitnessTracker/Features/Home/HomeView.swift` — modify: add
  the pending-observations card (Task 6).
- `FitnessTracker/FitnessTracker/Features/Home/PendingObservationCard.swift`
  — **create** (Task 6).
- Tests: `MeasurementGuardrailTests.swift`, `MemoryKeeperDTOTests.swift`,
  `MemoryKeeperPromptBuilderTests.swift`, `MemoryKeeperCoordinatorTests.swift`
  — all **create**. `HistoryExportManagerTests.swift`,
  `SwiftDataMetricsRepositoryTests.swift`, `HealthAndMemoryModelsTests.swift`
  — modify/extend (Task 1).

---

## Task 1: `ObservationModel.confirmed` + filtered reads

**Files:**
- Modify: `Models/HealthModels.swift`
- Modify: `Export/HistoryExportManager.swift`
- Modify: `Metrics/SwiftDataMetricsRepository.swift`
- Modify: `FitnessTrackerTests/HealthAndMemoryModelsTests.swift`
- Modify: `FitnessTrackerTests/HistoryExportManagerTests.swift`
- Modify: `FitnessTrackerTests/SwiftDataMetricsRepositoryTests.swift`

**Interfaces:**
- Produces: `ObservationModel.confirmed: Bool` (default `true`), so every
  existing/manually-entered observation is confirmed by construction and only
  Task 4's AI write path ever sets it `false`.

- [ ] **Step 1: Add `confirmed` to `ObservationModel`**

In `Models/HealthModels.swift`, add the stored property and default it in
`init`:

```swift
@Model
final class ObservationModel {
    var kind: String
    var value: Double
    var unit: String
    var timestamp: Date
    var contextJSON: String
    var sessionID: UUID?
    var entryExerciseID: String?
    /// `false` only for AI-derived rows awaiting your confirmation (design
    /// spec §6) — every manually-entered or deterministically-computed
    /// observation is confirmed by construction.
    var confirmed: Bool

    init(kind: String, value: Double, unit: String, timestamp: Date) {
        self.kind = kind
        self.value = value
        self.unit = unit
        self.timestamp = timestamp
        self.contextJSON = "{}"
        self.sessionID = nil
        self.entryExerciseID = nil
        self.confirmed = true
    }
}
```

- [ ] **Step 2: Filter `HistoryExportManager.exportFullJSONData`**

In `Export/HistoryExportManager.swift`, change the observations loop to skip
unconfirmed rows — an AI-derived number pending your review must not feed
back into the AI's own next `QueryTrainingDataTool` reasoning:

```swift
for o in observations where o.confirmed {
    observationsList.append([
        "kind": o.kind,
        "value": o.value,
        "unit": o.unit,
        "timestamp": df.string(from: o.timestamp),
        "sessionId": o.sessionID?.uuidString as Any,
        "entryExerciseId": o.entryExerciseID as Any
    ])
}
```

- [ ] **Step 3: Filter `SwiftDataMetricsRepository.observations(kind:since:)`**

In `Metrics/SwiftDataMetricsRepository.swift`:

```swift
func observations(kind: String, since: Date?) -> [ObservationSnapshot] {
    ((try? context.fetch(FetchDescriptor<ObservationModel>())) ?? [])
        .filter { $0.confirmed }
        .map { $0.toSnapshot() }
        .filter { o in o.kind == kind && (since.map { o.timestamp >= $0 } ?? true) }
}
```

- [ ] **Step 4: Test — `confirmed` defaults `true` and round-trips**

In `FitnessTrackerTests/HealthAndMemoryModelsTests.swift`, add:

```swift
@Test func observationConfirmedDefaultsTrue() {
    let obs = ObservationModel(kind: "bodyweight", value: 80, unit: "kg", timestamp: Date())
    #expect(obs.confirmed)
}
```

- [ ] **Step 5: Test — unconfirmed observations excluded from the export**

In `FitnessTrackerTests/HistoryExportManagerTests.swift`, find the existing
test container setup pattern (an in-memory `ModelContainer`/`ModelContext`)
and add:

```swift
@Test func excludesUnconfirmedObservationsFromExport() throws {
    let cont = try container()   // reuse this file's existing container() helper
    let ctx = ModelContext(cont)
    let confirmed = ObservationModel(kind: "bodyweight", value: 80, unit: "kg", timestamp: Date())
    let unconfirmed = ObservationModel(kind: "bodyFatPercent", value: 18, unit: "%", timestamp: Date())
    unconfirmed.confirmed = false
    ctx.insert(confirmed)
    ctx.insert(unconfirmed)
    try ctx.save()

    let data = HistoryExportManager.exportFullJSONData(context: ctx, catalog: catalog())! // reuse this file's existing catalog() helper
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let observationsList = json["observations"] as! [[String: Any]]

    #expect(observationsList.count == 1)
    #expect(observationsList[0]["kind"] as? String == "bodyweight")
}
```

**Note for the implementer:** if `HistoryExportManagerTests.swift` doesn't
already have `container()`/`catalog()` helpers with these exact names, open
the file first and match whatever it actually calls them — every other test
in that file already builds a container and catalog somehow.

- [ ] **Step 6: Test — unconfirmed observations excluded from repository reads**

In `FitnessTrackerTests/SwiftDataMetricsRepositoryTests.swift`, extend the
existing `bodyweight` observation test area with:

```swift
@Test func unconfirmedObservationExcludedFromRead() throws {
    let cont = try container()
    let ctx = ModelContext(cont)
    let confirmed = ObservationModel(kind: "bodyweight", value: 80.5, unit: "kg", timestamp: date(2026, 2, 3))
    let unconfirmed = ObservationModel(kind: "bodyweight", value: 999, unit: "kg", timestamp: date(2026, 2, 4))
    unconfirmed.confirmed = false
    ctx.insert(confirmed)
    ctx.insert(unconfirmed)
    try ctx.save()

    let sut = SwiftDataMetricsRepository(context: ctx, catalog: catalog(), plannedSessionsPerWeek: 3)
    let results = sut.observations(kind: "bodyweight", since: nil)

    #expect(results.count == 1)
    #expect(results[0].value == 80.5)
}
```

**Note for the implementer:** match this file's actual helper names
(`container()`, `catalog()`, `date(_:_:_:)`) — they already exist per the
pre-existing tests at lines ~122 and ~189 of this file; don't redeclare them.

- [ ] **Step 7: Build and test**

Run: `xcodebuild test -scheme FitnessTracker -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' -project FitnessTracker/FitnessTracker.xcodeproj 2>&1 | tail -30`
Expected: green, including the three new tests.

- [ ] **Step 8: Commit**

```bash
git add FitnessTracker/FitnessTracker/Models/HealthModels.swift \
        FitnessTracker/FitnessTracker/Export/HistoryExportManager.swift \
        FitnessTracker/FitnessTracker/Metrics/SwiftDataMetricsRepository.swift \
        FitnessTracker/FitnessTrackerTests/HealthAndMemoryModelsTests.swift \
        FitnessTracker/FitnessTrackerTests/HistoryExportManagerTests.swift \
        FitnessTracker/FitnessTrackerTests/SwiftDataMetricsRepositoryTests.swift
git commit -m "Add ObservationModel.confirmed, exclude unconfirmed rows from export and repository reads"
```

---

## Task 2: `MeasurementGuardrail`

**Files:**
- Create: `FitnessTracker/FitnessTracker/AI/MeasurementGuardrail.swift`
- Test: `FitnessTrackerTests/MeasurementGuardrailTests.swift`

**Interfaces:**
- Produces: `enum MeasurementGuardrail { static func isPlausible(kind: String, value: Double) -> Bool }`
  — consumed by Task 4's `MemoryKeeperCoordinator`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import FitnessTracker

@Suite struct MeasurementGuardrailTests {
    @Test func acceptsPlausibleBodyweight() {
        #expect(MeasurementGuardrail.isPlausible(kind: "bodyweight", value: 82.5))
    }

    @Test func rejectsImplausibleBodyweight() {
        #expect(!MeasurementGuardrail.isPlausible(kind: "bodyweight", value: 900))
        #expect(!MeasurementGuardrail.isPlausible(kind: "bodyweight", value: -5))
    }

    @Test func acceptsPlausibleBodyFatPercent() {
        #expect(MeasurementGuardrail.isPlausible(kind: "bodyFatPercent", value: 18.2))
    }

    @Test func rejectsImplausibleBodyFatPercent() {
        #expect(!MeasurementGuardrail.isPlausible(kind: "bodyFatPercent", value: 95))
        #expect(!MeasurementGuardrail.isPlausible(kind: "bodyFatPercent", value: 0))
    }

    @Test func acceptsPlausibleMuscleMass() {
        #expect(MeasurementGuardrail.isPlausible(kind: "muscleMassKg", value: 35))
    }

    @Test func rejectsUnknownKind() {
        #expect(!MeasurementGuardrail.isPlausible(kind: "shoeSize", value: 10))
    }

    @Test func rejectsBoundaryValuesExactlyAtTheEdge() {
        // Bounds are exclusive of the implausible extremes but must still
        // accept realistic edge cases without off-by-one rejection.
        #expect(MeasurementGuardrail.isPlausible(kind: "bodyweight", value: 30))
        #expect(MeasurementGuardrail.isPlausible(kind: "bodyweight", value: 300))
        #expect(!MeasurementGuardrail.isPlausible(kind: "bodyweight", value: 29.9))
        #expect(!MeasurementGuardrail.isPlausible(kind: "bodyweight", value: 300.1))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme FitnessTracker -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' -project FitnessTracker/FitnessTracker.xcodeproj -only-testing:FitnessTrackerTests/MeasurementGuardrailTests 2>&1 | tail -30`
Expected: FAIL — `MeasurementGuardrail` not defined.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Plausibility bounds for AI-derived `ObservationModel` writes (design spec
/// §6). An unrecognized `kind` is rejected outright — this call only ever
/// writes a kind the app already knows how to chart, never an invented one.
/// Values passing this check still land with `confirmed = false`; this is
/// "not obviously garbage," not "verified."
enum MeasurementGuardrail {
    private static let bounds: [String: ClosedRange<Double>] = [
        "bodyweight": 30...300,
        "bodyFatPercent": 3...60,
        "muscleMassKg": 10...150
    ]

    static func isPlausible(kind: String, value: Double) -> Bool {
        guard let range = bounds[kind] else { return false }
        return range.contains(value)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme FitnessTracker -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' -project FitnessTracker/FitnessTracker.xcodeproj -only-testing:FitnessTrackerTests/MeasurementGuardrailTests 2>&1 | tail -30`
Expected: PASS, all 7 tests.

- [ ] **Step 5: Commit**

```bash
git add FitnessTracker/FitnessTracker/AI/MeasurementGuardrail.swift \
        FitnessTracker/FitnessTrackerTests/MeasurementGuardrailTests.swift
git commit -m "Add MeasurementGuardrail: plausibility bounds for AI-derived measurements"
```

---

## Task 3: `MemoryKeeperDTO` + `MemoryKeeperPromptBuilder`

**Files:**
- Create: `FitnessTracker/FitnessTracker/AI/MemoryKeeperDTO.swift`
- Create: `FitnessTracker/FitnessTracker/AI/MemoryKeeperPromptBuilder.swift`
- Test: `FitnessTrackerTests/MemoryKeeperDTOTests.swift`
- Test: `FitnessTrackerTests/MemoryKeeperPromptBuilderTests.swift`

**Interfaces:**
- Consumes: `MemoryCandidate`, `CandidateRelation`, `MemoryKind`, `MemoryTags`
  (existing, `CoachMemory` module), `CompletedSessionSnapshot`,
  `DailyCheckinSnapshot` (existing, `Metrics` module).
- Produces: `struct MemoryKeeperDTO: Codable, Sendable { let memoryCandidates:
  [MemoryCandidateDTO]; let measurementCandidates: [MeasurementCandidateDTO] }`,
  `MemoryCandidateDTO.toDomain() -> MemoryCandidate?` (nil when malformed —
  never crashes on a bad model output),
  `enum MemoryKeeperPromptBuilder { static let finalSchema: JSONSchema;
  static func system() -> String; static func user(session:
  CompletedSessionSnapshot, checkin: DailyCheckinSnapshot?, memoryDigest:
  String) -> String }` — consumed by Task 4's `MemoryKeeperCoordinator`.

- [ ] **Step 1: Write the failing DTO tests**

```swift
import Testing
import Foundation
import CoachMemory
@testable import FitnessTracker

@Suite struct MemoryKeeperDTOTests {
    @Test func decodesFullShapeFromJSON() throws {
        let json = """
        {
          "memoryCandidates": [
            {"kind": "constraint", "statement": "Avoid overhead pressing — shoulder pain reported.",
             "action": "Swap overhead press for chest press", "exerciseID": null, "muscle": "shoulders",
             "equipment": null, "freeTags": [], "relation": "new", "relatedMemoryID": null}
          ],
          "measurementCandidates": [
            {"kind": "bodyFatPercent", "value": 18.2, "unit": "%"}
          ]
        }
        """
        let dto = try JSONDecoder().decode(MemoryKeeperDTO.self, from: Data(json.utf8))
        #expect(dto.memoryCandidates.count == 1)
        #expect(dto.measurementCandidates.count == 1)
        #expect(dto.measurementCandidates[0].value == 18.2)
    }

    @Test func decodesEmptyArrays() throws {
        let json = """
        {"memoryCandidates": [], "measurementCandidates": []}
        """
        let dto = try JSONDecoder().decode(MemoryKeeperDTO.self, from: Data(json.utf8))
        #expect(dto.memoryCandidates.isEmpty)
        #expect(dto.measurementCandidates.isEmpty)
    }

    @Test func toDomainMapsNewRelation() {
        let dto = MemoryCandidateDTO(kind: "preference", statement: "Prefers dumbbells over barbells for pressing.",
                                     action: nil, exerciseID: nil, muscle: nil, equipment: "dumbbell",
                                     freeTags: ["preference"], relation: "new", relatedMemoryID: nil)
        let candidate = dto.toDomain()
        #expect(candidate?.kind == .preference)
        #expect(candidate?.relation == .new)
        #expect(candidate?.tags.equipment == .dumbbell)
    }

    @Test func toDomainMapsReinforcesWithValidUUID() {
        let id = UUID()
        let dto = MemoryCandidateDTO(kind: "observation", statement: "Consistently sore after leg day.",
                                     action: nil, exerciseID: nil, muscle: "quads", equipment: nil,
                                     freeTags: [], relation: "reinforces", relatedMemoryID: id.uuidString)
        let candidate = dto.toDomain()
        #expect(candidate?.relation == .reinforces(id))
    }

    @Test func toDomainFallsBackToNewWhenReinforcesHasNoID() {
        let dto = MemoryCandidateDTO(kind: "observation", statement: "Test.",
                                     action: nil, exerciseID: nil, muscle: nil, equipment: nil,
                                     freeTags: [], relation: "reinforces", relatedMemoryID: nil)
        #expect(dto.toDomain()?.relation == .new)
    }

    @Test func toDomainReturnsNilForUnknownKind() {
        let dto = MemoryCandidateDTO(kind: "bogus", statement: "Test.",
                                     action: nil, exerciseID: nil, muscle: nil, equipment: nil,
                                     freeTags: [], relation: "new", relatedMemoryID: nil)
        #expect(dto.toDomain() == nil)
    }

    @Test func toDomainReturnsNilForUnknownRelation() {
        let dto = MemoryCandidateDTO(kind: "preference", statement: "Test.",
                                     action: nil, exerciseID: nil, muscle: nil, equipment: nil,
                                     freeTags: [], relation: "bogus", relatedMemoryID: nil)
        #expect(dto.toDomain() == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme FitnessTracker -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' -project FitnessTracker/FitnessTracker.xcodeproj -only-testing:FitnessTrackerTests/MemoryKeeperDTOTests 2>&1 | tail -30`
Expected: FAIL — types not defined.

- [ ] **Step 3: Implement `MemoryKeeperDTO.swift`**

```swift
import Foundation
import FitnessDomain
import CoachMemory

struct MeasurementCandidateDTO: Codable, Sendable {
    let kind: String
    let value: Double
    let unit: String
}

struct MemoryCandidateDTO: Codable, Sendable {
    let kind: String
    let statement: String
    let action: String?
    let exerciseID: String?
    let muscle: String?
    let equipment: String?
    let freeTags: [String]
    let relation: String
    let relatedMemoryID: String?

    /// `nil` on any malformed field — an unrecognized `kind`/`relation`, or a
    /// non-`new` relation missing a parseable id. The model never crashes the
    /// coordinator; a malformed candidate is simply dropped (design spec §5:
    /// "drop the candidate ... treat as .new per reconcile's own unknown-id
    /// handling" applies only when the id itself fails to parse but relation
    /// is otherwise valid — an unparseable relation/kind drops entirely).
    func toDomain() -> MemoryCandidate? {
        guard let memoryKind = MemoryKind(rawValue: kind) else { return nil }

        let relationValue: CandidateRelation
        switch relation {
        case "new":
            relationValue = .new
        case "reinforces":
            if let idString = relatedMemoryID, let id = UUID(uuidString: idString) {
                relationValue = .reinforces(id)
            } else {
                relationValue = .new   // unknown/missing id -> treat as new, per reconcile's own handling
            }
        case "contradicts":
            if let idString = relatedMemoryID, let id = UUID(uuidString: idString) {
                relationValue = .contradicts(id)
            } else {
                relationValue = .new
            }
        default:
            return nil
        }

        let tags = MemoryTags(
            exerciseID: exerciseID,
            muscle: muscle.flatMap(MuscleGroup.init(rawValue:)),
            equipment: equipment.flatMap(Equipment.init(rawValue:)),
            freeTags: freeTags
        )

        return MemoryCandidate(kind: memoryKind, statement: statement, action: action,
                               tags: tags, relation: relationValue)
    }
}

nonisolated struct MemoryKeeperDTO: Codable, Sendable {
    let memoryCandidates: [MemoryCandidateDTO]
    let measurementCandidates: [MeasurementCandidateDTO]
}
```

**Note for the implementer:** `CandidateRelation` needs `Equatable` to make
`#expect(candidate?.relation == .reinforces(id))` compile — check
`FitnessCore/Sources/CoachMemory/MemoryConsolidation.swift` first; it's
already declared `Sendable, Equatable`, so no change needed there.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme FitnessTracker -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' -project FitnessTracker/FitnessTracker.xcodeproj -only-testing:FitnessTrackerTests/MemoryKeeperDTOTests 2>&1 | tail -30`
Expected: PASS, all 7 tests.

- [ ] **Step 5: Write the failing prompt builder tests**

```swift
import Testing
import Foundation
import FitnessDomain
import Metrics
@testable import FitnessTracker

@Suite struct MemoryKeeperPromptBuilderTests {
    private func session(note: String?) -> CompletedSessionSnapshot {
        CompletedSessionSnapshot(
            id: UUID(), date: Date(), weekday: 2, timeOfDayMinutes: 600,
            plannedDurationMin: 60, actualDurationMin: 55, energy: .normal,
            timeAvailableMin: 60, outcome: .complete, partialReason: nil,
            coachSource: .ai, plannedSessionID: nil, entries: [], overallNote: note
        )
    }

    @Test func systemPromptStatesTheTwoOutputArrays() {
        let prompt = MemoryKeeperPromptBuilder.system()
        #expect(prompt.contains("memoryCandidates"))
        #expect(prompt.contains("measurementCandidates"))
    }

    @Test func userPromptIncludesOverallNote() {
        let prompt = MemoryKeeperPromptBuilder.user(
            session: session(note: "Shoulder felt sore during overhead press."),
            checkin: nil, memoryDigest: ""
        )
        #expect(prompt.contains("Shoulder felt sore during overhead press."))
    }

    @Test func userPromptIncludesCheckinWhenPresent() {
        let checkin = DailyCheckinSnapshot(date: Date(), sleepQuality: 3, soreness: 7, note: "Legs still sore from Monday")
        let prompt = MemoryKeeperPromptBuilder.user(session: session(note: nil), checkin: checkin, memoryDigest: "")
        #expect(prompt.contains("Legs still sore from Monday"))
        #expect(prompt.contains("7"))
    }

    @Test func userPromptOmitsCheckinSectionWhenNil() {
        let prompt = MemoryKeeperPromptBuilder.user(session: session(note: nil), checkin: nil, memoryDigest: "")
        #expect(!prompt.contains("Today's check-in"))
    }

    @Test func userPromptIncludesMemoryDigestWhenNonEmpty() {
        let prompt = MemoryKeeperPromptBuilder.user(session: session(note: nil), checkin: nil,
                                                     memoryDigest: "- Prefers dumbbells over barbells")
        #expect(prompt.contains("Prefers dumbbells over barbells"))
    }
}
```

- [ ] **Step 6: Run tests to verify they fail**

Run: `xcodebuild test -scheme FitnessTracker -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' -project FitnessTracker/FitnessTracker.xcodeproj -only-testing:FitnessTrackerTests/MemoryKeeperPromptBuilderTests 2>&1 | tail -30`
Expected: FAIL — `MemoryKeeperPromptBuilder` not defined.

- [ ] **Step 7: Implement `MemoryKeeperPromptBuilder.swift`**

```swift
import Foundation
import FitnessDomain
import Metrics
import LLMKit

nonisolated enum MemoryKeeperPromptBuilder {
    static let finalSchema = JSONSchema(json: """
    {
      "memoryCandidates": [{"kind": "preference|constraint|observation|goal|responsePattern",
                            "statement": "string", "action": "string|null",
                            "exerciseID": "string|null", "muscle": "string|null",
                            "equipment": "string|null", "freeTags": ["string"],
                            "relation": "new|reinforces|contradicts", "relatedMemoryID": "string|null"}],
      "measurementCandidates": [{"kind": "string", "value": "number", "unit": "string"}]
    }
    """)

    /// The persona is the same coach voice as `FinalizePromptBuilder`, but the
    /// job here is purely observational — this call never changes anything,
    /// it only notices and remembers.
    static func system() -> String {
        """
        You are an experienced, direct personal trainer reviewing a session \
        that just finished. You do not change anything about it — you only \
        decide what, if anything, is worth remembering for future sessions.

        Return two arrays:
        - memoryCandidates: durable facts about this athlete worth carrying \
        forward — a stated preference, an injury or hard constraint, a \
        recurring pattern, a goal, or a notable observation. Most sessions \
        produce none; an empty array is a normal, expected answer, not a \
        failure. Set "relation" to "new" for a fact you haven't seen before, \
        "reinforces" (with "relatedMemoryID") when it confirms an existing \
        memory you were given, or "contradicts" (with "relatedMemoryID") when \
        it supersedes one.
        - measurementCandidates: only an explicit numeric body-composition \
        measurement the athlete reported in their notes (e.g. an InBody scan \
        result) — never a number you calculated yourself, and never a set/rep/ \
        load figure from the workout itself.

        Only extract what is actually stated. Do not infer an injury from a \
        single hard set, and do not invent a preference from one exercise \
        choice. Respond only in the required JSON shape.
        """
    }

    static func user(
        session: CompletedSessionSnapshot,
        checkin: DailyCheckinSnapshot?,
        memoryDigest: String
    ) -> String {
        let noteSection = session.overallNote.map { "Athlete's note on today's session: \($0)" }
            ?? "No note left on today's session."

        let checkinSection = checkin.map { c -> String in
            var lines = ["Today's check-in:"]
            if let sleep = c.sleepQuality { lines.append("- Sleep quality: \(sleep)/10") }
            if let soreness = c.soreness { lines.append("- Soreness: \(soreness)/10") }
            if let note = c.note, !note.isEmpty { lines.append("- Note: \(note)") }
            return lines.joined(separator: "\n")
        } ?? ""

        let memorySection = memoryDigest.isEmpty
            ? "No standing memory yet for this athlete."
            : "What you already know about this athlete:\n\(memoryDigest)"

        let sections = [
            "Session outcome: \(session.outcome), energy: \(session.energy).",
            noteSection,
            checkinSection,
            memorySection,
            "Decide what, if anything, is worth remembering from this session."
        ].filter { !$0.isEmpty }

        return sections.joined(separator: "\n\n")
    }
}
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `xcodebuild test -scheme FitnessTracker -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' -project FitnessTracker/FitnessTracker.xcodeproj -only-testing:FitnessTrackerTests/MemoryKeeperPromptBuilderTests 2>&1 | tail -30`
Expected: PASS, all 5 tests.

- [ ] **Step 9: Commit**

```bash
git add FitnessTracker/FitnessTracker/AI/MemoryKeeperDTO.swift \
        FitnessTracker/FitnessTracker/AI/MemoryKeeperPromptBuilder.swift \
        FitnessTracker/FitnessTrackerTests/MemoryKeeperDTOTests.swift \
        FitnessTracker/FitnessTrackerTests/MemoryKeeperPromptBuilderTests.swift
git commit -m "Add MemoryKeeperDTO and MemoryKeeperPromptBuilder"
```

---

## Task 4: `MemoryKeeperCoordinator` — the orchestrator

**Files:**
- Create: `FitnessTracker/FitnessTracker/AI/MemoryKeeperCoordinator.swift`
- Test: `FitnessTrackerTests/MemoryKeeperCoordinatorTests.swift`

**Interfaces:**
- Consumes: `ToolLoopRunner`/`ToolLoopResult`/`CallOutcome` (Task 5/7 of the
  finalize plan, already built), `ToolRegistry`/`QueryTrainingDataTool`
  (existing), `MemoryKeeperDTO`/`MemoryKeeperPromptBuilder` (Task 3),
  `MeasurementGuardrail` (Task 2), `MemoryRecall.select`,
  `MemoryConsolidation.reconcile` (existing, `CoachMemory` module),
  `coachMemoryModel(from:)` (existing, `Metrics/ModelSnapshotMapping.swift`).
- Produces: `@MainActor protocol MemoryKeeperRunning { func run(session:
  CompletedSessionSnapshot) async }`, `@MainActor struct
  MemoryKeeperCoordinator: MemoryKeeperRunning` — consumed by Task 5's
  `SessionRunner`/`SessionContainerView` wiring.

- [ ] **Step 1: Write the failing coordinator tests**

```swift
import Testing
import SwiftData
import Foundation
import FitnessDomain
import ExerciseCatalog
import Metrics
import CoachMemory
@testable import FitnessTracker

@MainActor
@Suite struct MemoryKeeperCoordinatorTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: UserProfile.self, StoredPlan.self, ProviderProfile.self, AICallRecord.self,
            CompletedSessionModel.self, CompletedEntryModel.self, LoggedSetModel.self,
            BodyweightEntryModel.self, DailyCheckinModel.self, ObservationModel.self,
            PersonalRecordModel.self, CoachMemoryModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func exercise(_ id: String) -> Exercise {
        Exercise(id: id, name: id, primaryMuscle: .chest, secondaryMuscles: [],
                 equipment: .barbell, mechanic: .compound, force: .push,
                 difficulty: .intermediate, isUnilateral: false, instructions: [], imagePaths: [])
    }

    private func catalog() -> CatalogStore { CatalogStore(exercises: [exercise("bench")]) }

    private func session(note: String?) -> CompletedSessionSnapshot {
        CompletedSessionSnapshot(
            id: UUID(), date: Date(), weekday: 2, timeOfDayMinutes: 600,
            plannedDurationMin: 60, actualDurationMin: 55, energy: .normal,
            timeAvailableMin: 60, outcome: .complete, partialReason: nil,
            coachSource: .ai, plannedSessionID: nil, entries: [], overallNote: note
        )
    }

    @Test func writesNewMemoryFromModelOutput() throws {
        let cont = try container()
        let ctx = ModelContext(cont)
        let finalTurn = """
        {"decision":"final","final":{
          "memoryCandidates":[{"kind":"constraint","statement":"Shoulder pain on overhead press.",
            "action":"Avoid overhead pressing","exerciseID":null,"muscle":"shoulders","equipment":null,
            "freeTags":[],"relation":"new","relatedMemoryID":null}],
          "measurementCandidates":[]
        }}
        """
        let provider = StubLLMProvider(responses: [.success(finalTurn)])
        let coordinator = MemoryKeeperCoordinator(
            catalog: catalog(), context: ctx, provider: provider, activeProfile: nil, memories: []
        )

        await coordinator.run(session: session(note: "Shoulder hurt on overhead press today."))

        let memories = try ctx.fetch(FetchDescriptor<CoachMemoryModel>())
        #expect(memories.count == 1)
        #expect(memories[0].statement == "Shoulder pain on overhead press.")
        #expect(memories[0].kindRaw == "constraint")
    }

    @Test func writesUnconfirmedObservationFromMeasurementCandidate() throws {
        let cont = try container()
        let ctx = ModelContext(cont)
        let finalTurn = """
        {"decision":"final","final":{
          "memoryCandidates":[],
          "measurementCandidates":[{"kind":"bodyFatPercent","value":18.2,"unit":"%"}]
        }}
        """
        let provider = StubLLMProvider(responses: [.success(finalTurn)])
        let coordinator = MemoryKeeperCoordinator(
            catalog: catalog(), context: ctx, provider: provider, activeProfile: nil, memories: []
        )

        await coordinator.run(session: session(note: "InBody scan today: 18.2% body fat."))

        let observations = try ctx.fetch(FetchDescriptor<ObservationModel>())
        #expect(observations.count == 1)
        #expect(observations[0].confirmed == false)
        #expect(observations[0].value == 18.2)
    }

    @Test func rejectsImplausibleMeasurementCandidate() throws {
        let cont = try container()
        let ctx = ModelContext(cont)
        let finalTurn = """
        {"decision":"final","final":{
          "memoryCandidates":[],
          "measurementCandidates":[{"kind":"bodyFatPercent","value":250,"unit":"%"}]
        }}
        """
        let provider = StubLLMProvider(responses: [.success(finalTurn)])
        let coordinator = MemoryKeeperCoordinator(
            catalog: catalog(), context: ctx, provider: provider, activeProfile: nil, memories: []
        )

        await coordinator.run(session: session(note: "Bad reading."))

        let observations = try ctx.fetch(FetchDescriptor<ObservationModel>())
        #expect(observations.isEmpty)
    }

    @Test func noProviderIsANoOp() throws {
        let cont = try container()
        let ctx = ModelContext(cont)
        let coordinator = MemoryKeeperCoordinator(
            catalog: catalog(), context: ctx, provider: nil, activeProfile: nil, memories: []
        )

        await coordinator.run(session: session(note: "Anything"))

        #expect(try ctx.fetch(FetchDescriptor<CoachMemoryModel>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<AICallRecord>()).isEmpty)
    }

    @Test func providerFailureIsASilentNoOp() throws {
        let cont = try container()
        let ctx = ModelContext(cont)
        let provider = StubLLMProvider(responses: [.failure(.emptyResponse)])
        let coordinator = MemoryKeeperCoordinator(
            catalog: catalog(), context: ctx, provider: provider, activeProfile: nil, memories: []
        )

        await coordinator.run(session: session(note: "Anything"))

        #expect(try ctx.fetch(FetchDescriptor<CoachMemoryModel>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<AICallRecord>()).isEmpty)
    }

    @Test func emptyOutputWritesNothingButStillRecordsTheCall() throws {
        let cont = try container()
        let ctx = ModelContext(cont)
        let finalTurn = """
        {"decision":"final","final":{"memoryCandidates":[],"measurementCandidates":[]}}
        """
        let provider = StubLLMProvider(responses: [.success(finalTurn)])
        let coordinator = MemoryKeeperCoordinator(
            catalog: catalog(), context: ctx, provider: provider, activeProfile: nil, memories: []
        )

        await coordinator.run(session: session(note: "Uneventful session."))

        #expect(try ctx.fetch(FetchDescriptor<CoachMemoryModel>()).isEmpty)
        let calls = try ctx.fetch(FetchDescriptor<AICallRecord>())
        #expect(calls.count == 1)
        #expect(calls[0].callType == "memoryKeeper")
    }
}
```

**Note for the implementer:** `StubLLMProvider` and `LLMError` already exist
(`FitnessTrackerTests/StubLLMProvider.swift`, used by
`ToolLoopRunnerTests.swift`/`FinalizeDTOTests`-style suites) — reuse them,
don't redeclare.

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme FitnessTracker -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' -project FitnessTracker/FitnessTracker.xcodeproj -only-testing:FitnessTrackerTests/MemoryKeeperCoordinatorTests 2>&1 | tail -30`
Expected: FAIL — `MemoryKeeperCoordinator` not defined.

- [ ] **Step 3: Implement `MemoryKeeperCoordinator.swift`**

```swift
import Foundation
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics
import CoachMemory
import LLMKit

/// The call `MemoryConsolidation.reconcile` has been waiting for since it was
/// built (design spec §5.2(1), `docs/specs/2026-09-05-memory-keeper-call-design.md`).
/// Fires after a session finishes, reads the session + today's check-in + the
/// live memory set, and proposes memory candidates (routed through the
/// existing deterministic `reconcile`) and measurement candidates (routed
/// through `MeasurementGuardrail`, landing unconfirmed for you to approve).
///
/// Unlike `SessionFinalizeCoordinator`, this call has no obligation to
/// produce anything and never falls back to anything: no provider, a thrown
/// error, an exceeded tool-loop cap, or a decode failure are all silent,
/// valid no-ops. Nothing is written, and no `AICallRecord` for a call that
/// never actually ran.
@MainActor
struct MemoryKeeperCoordinator: MemoryKeeperRunning {
    let catalog: CatalogStore
    let context: ModelContext
    let provider: (any LLMProvider)?
    let activeProfile: ProviderProfile?
    let memories: [CoachMemory]

    func run(session: CompletedSessionSnapshot) async {
        guard let provider else { return }

        let checkin = (try? context.fetch(FetchDescriptor<DailyCheckinModel>()))?
            .first { Calendar.isoUTC.isDate($0.date, inSameDayAs: session.date) }
            .map { DailyCheckinSnapshot(date: $0.date, sleepQuality: $0.sleepQuality, soreness: $0.soreness, note: $0.note) }

        let recalled = MemoryRecall.select(
            from: memories,
            context: RecallContext(exerciseIDs: Set(session.entries.map(\.exerciseID))),
            now: .now
        )

        let exportJSON = HistoryExportManager.exportFullJSONData(context: context, catalog: catalog) ?? Data("{}".utf8)
        let tools = ToolRegistry(tools: [QueryTrainingDataTool(exportJSON: exportJSON)])

        let system = MemoryKeeperPromptBuilder.system()
        let user = MemoryKeeperPromptBuilder.user(session: session, checkin: checkin, memoryDigest: recalled.digest)

        let calls: [CallOutcome]
        let dto: MemoryKeeperDTO
        do {
            let loopResult: ToolLoopResult<MemoryKeeperDTO> = try await ToolLoopRunner().run(
                system: system, initialUser: user,
                finalSchema: MemoryKeeperPromptBuilder.finalSchema,
                tools: tools, provider: provider
            )
            calls = loopResult.calls
            dto = loopResult.value
        } catch ToolLoopError.exceededMaxIterations(let partialCalls) {
            // Still ran real, billable calls even though it never converged.
            recordCalls(partialCalls)
            return
        } catch {
            return // provider/decode failure — silent no-op, nothing to bill.
        }

        recordCalls(calls)
        applyMemoryCandidates(dto.memoryCandidates)
        applyMeasurementCandidates(dto.measurementCandidates, sessionID: session.id)
        try? context.save()
    }

    private func applyMemoryCandidates(_ dtos: [MemoryCandidateDTO]) {
        let candidates = dtos.compactMap { $0.toDomain() }
        guard !candidates.isEmpty else { return }

        let existingDomain = memories
        let result = MemoryConsolidation.reconcile(existing: existingDomain, candidates: candidates, now: .now)

        for memory in result.writes {
            context.insert(coachMemoryModel(from: memory))
        }
        let existingModels = (try? context.fetch(FetchDescriptor<CoachMemoryModel>())) ?? []
        for memory in result.updated + result.retired {
            guard let model = existingModels.first(where: { $0.id == memory.id }) else { continue }
            model.confidence = memory.confidence
            model.lastConfirmedAt = memory.lastConfirmedAt
            model.action = memory.action
            model.supersededBy = memory.supersededBy
            model.retiredByCap = memory.retiredByCap
        }
    }

    private func applyMeasurementCandidates(_ dtos: [MeasurementCandidateDTO], sessionID: UUID) {
        for dto in dtos where MeasurementGuardrail.isPlausible(kind: dto.kind, value: dto.value) {
            let model = ObservationModel(kind: dto.kind, value: dto.value, unit: dto.unit, timestamp: .now)
            model.confirmed = false
            model.sessionID = sessionID
            context.insert(model)
        }
    }

    private func recordCalls(_ calls: [CallOutcome]) {
        guard !calls.isEmpty else { return }
        for call in calls {
            let costUSD: Double
            if let activeProfile {
                costUSD = AICallRecord.cost(inputTokens: call.inputTokens, outputTokens: call.outputTokens,
                                            cachedTokens: call.cachedTokens,
                                            pricePerMTokIn: activeProfile.pricePerMTokIn,
                                            pricePerMTokOut: activeProfile.pricePerMTokOut,
                                            pricePerMTokCached: activeProfile.pricePerMTokCached)
            } else {
                costUSD = 0
            }
            let record = AICallRecord(callType: "memoryKeeper",
                                      providerDisplayName: activeProfile?.displayName ?? "—",
                                      modelID: activeProfile?.modelID ?? "—",
                                      inputTokens: call.inputTokens, outputTokens: call.outputTokens,
                                      cachedTokens: call.cachedTokens, costUSD: costUSD,
                                      success: call.succeeded, usedFallback: false)
            context.insert(record)
        }
        try? context.save()
    }
}

@MainActor
protocol MemoryKeeperRunning {
    func run(session: CompletedSessionSnapshot) async
}
```

**Note for the implementer:** `recordCalls` is called before `applyMemory-
Candidates`/`applyMeasurementCandidates` and saves immediately — this way,
even if something in the apply step went wrong, the billing record (which
reflects real tokens already spent with the provider) is never lost. The
final `try? context.save()` at the end of `run` persists the memory/
observation writes; `recordCalls`' own `try? context.save()` is a second,
harmless save of the same context.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme FitnessTracker -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' -project FitnessTracker/FitnessTracker.xcodeproj -only-testing:FitnessTrackerTests/MemoryKeeperCoordinatorTests 2>&1 | tail -30`
Expected: PASS, all 6 tests.

- [ ] **Step 5: Commit**

```bash
git add FitnessTracker/FitnessTracker/AI/MemoryKeeperCoordinator.swift \
        FitnessTracker/FitnessTrackerTests/MemoryKeeperCoordinatorTests.swift
git commit -m "Add MemoryKeeperCoordinator: orchestrates memory-keeper call, consolidation, and measurement writes"
```

---

## Task 5: Wire the trigger into `SessionRunner.finish()`

**Files:**
- Modify: `Session/SessionRunner.swift`
- Modify: `Features/Session/SessionContainerView.swift`
- Test: `FitnessTrackerTests/SessionRunnerTests.swift`

**Interfaces:**
- Consumes: `MemoryKeeperRunning`, `MemoryKeeperCoordinator` (Task 4).
- Produces: `SessionRunner.init(..., memoryKeeper: (any MemoryKeeperRunning)? = nil)`
  — the default keeps every existing call site (10+ in
  `SessionRunnerTests.swift`, `ExerciseSwapTests.swift`) compiling unchanged.

- [ ] **Step 1: Add the optional dependency and fire it from `finish()`**

In `Session/SessionRunner.swift`, add the stored property and constructor
parameter:

```swift
private let finalizer: any SessionFinalizing
private let memoryKeeper: (any MemoryKeeperRunning)?
private let now: () -> Date

init(modelContext: ModelContext,
     catalog: CatalogStore,
     repository: any MetricsRepository,
     finalizer: any SessionFinalizing,
     memoryKeeper: (any MemoryKeeperRunning)? = nil,
     now: @escaping () -> Date = { .now }) {
    self.modelContext = modelContext
    self.catalog = catalog
    self.repository = repository
    self.finalizer = finalizer
    self.memoryKeeper = memoryKeeper
    self.now = now
}
```

Then, in `finish(partialReason:overallNote:)`, fire it as a detached,
non-blocking `Task` right after the session is persisted — the transition to
`.summary` on the next line must not wait on it:

```swift
func finish(partialReason: PartialReason?, overallNote: String?) {
    guard let session, session.finishedAt == nil else { return }   // F4: idempotent

    let outcome: SessionOutcome = orderedEntries.allSatisfy {
        $0.stateRaw == EntryState.done.rawValue && !$0.skipped
    } ? .complete : .partial

    Self.promoteWorkedEntries(of: session)

    let ts = now()
    session.finishedAt = ts
    session.actualDurationMin = Int((ts.timeIntervalSince(session.startedAt) / 60).rounded())
    session.outcomeRaw = outcome.rawValue
    session.partialReasonRaw = partialReason?.rawValue
    session.overallNote = overallNote
    try? modelContext.save()

    let new = Self.detectAndPersistPRs(for: session, in: modelContext)
    lastSessionPRs = new
    resolvedOutcome = outcome
    phase = .summary

    // Fire-and-forget: never blocks the transition to .summary above. A
    // finished/failed/skipped call is always a silent, valid outcome.
    if let memoryKeeper {
        let snapshot = session.toSnapshot()
        Task { await memoryKeeper.run(session: snapshot) }
    }
}
```

- [ ] **Step 2: Wire `SessionContainerView` to build it alongside the finalizer**

In `Features/Session/SessionContainerView.swift`, inside the `.task` block,
build the coordinator right next to `fin` and pass it through:

```swift
let fin: any SessionFinalizing = SessionFinalizeCoordinator(
    catalog: cat, context: context, provider: provider,
    activeProfile: activeProviderProfile,
    memories: allMemories.map { $0.toDomain() },
    ruleEngineFallback: ruleEngineFallback
)
let keeper: (any MemoryKeeperRunning)? = provider.map {
    MemoryKeeperCoordinator(catalog: cat, context: context, provider: $0,
                            activeProfile: activeProviderProfile,
                            memories: allMemories.map { $0.toDomain() })
}
runner = SessionRunner(modelContext: context, catalog: cat,
                       repository: repo, finalizer: fin, memoryKeeper: keeper)
```

**Note for the implementer:** `provider.map { ... }` naturally produces `nil`
when `provider` is `nil` (no active `ProviderProfile`, or the factory threw)
— matches `MemoryKeeperCoordinator.run`'s own no-provider no-op, so
`SessionRunner` need not special-case "no keeper" beyond the optional itself.

- [ ] **Step 3: Test — `finish()` still works with no `memoryKeeper` (default)**

`SessionRunnerTests.swift`'s existing 10 `runner.start(...)`/`finish(...)`
tests already construct `SessionRunner` without a `memoryKeeper` argument —
confirm they still compile and pass unchanged (they should, since the
parameter defaults to `nil` and `finish()`'s new code is gated behind
`if let memoryKeeper`). No new test file needed for this default-nil path;
Task 4's `noProviderIsANoOp` already covers the coordinator's own no-op
behavior, and Task 5's job is purely the wiring, not re-testing the
coordinator.

- [ ] **Step 4: Test — `finish()` fires the keeper when one is provided**

Add to `SessionRunnerTests.swift`:

```swift
@Test func finishFiresMemoryKeeperWhenOneIsProvided() async throws {
    final class SpyKeeper: MemoryKeeperRunning {
        var calledWithNote: String??
        func run(session: CompletedSessionSnapshot) async {
            calledWithNote = session.overallNote
        }
    }
    let cont = try container()
    let ctx = ModelContext(cont)
    let cat = catalog()
    let spy = SpyKeeper()
    let runner = SessionRunner(modelContext: ctx, catalog: cat, repository: emptyRepo(),
                               finalizer: finalizer(), memoryKeeper: spy, now: { Date() })

    await runner.start(planned: plannedSession(), energy: .normal, timeAvailableMin: 999)
    runner.finish(partialReason: nil, overallNote: "Felt strong today.")

    // finish() fires the keeper as a detached Task — give the run loop one
    // tick to let it actually execute before asserting.
    try await Task.sleep(for: .milliseconds(50))
    #expect(spy.calledWithNote == "Felt strong today.")
}
```

**Note for the implementer:** match this file's actual existing helper names
(`container()`, `catalog()`, `emptyRepo()`, `finalizer()`, `plannedSession()`)
— they already exist per the file's other tests; don't redeclare them. If
`SpyKeeper` needs `@MainActor` to satisfy `MemoryKeeperRunning`'s isolation,
add it (the enclosing `@Suite` is already `@MainActor` per this file's
existing declaration, so a nested class picks it up, but a top-level helper
class may need it explicit — check what the file already does for its other
test doubles).

- [ ] **Step 5: Build and test**

Run: `xcodebuild test -scheme FitnessTracker -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' -project FitnessTracker/FitnessTracker.xcodeproj 2>&1 | tail -30`
Expected: green, including the new test and all pre-existing `SessionRunnerTests`.

- [ ] **Step 6: Commit**

```bash
git add FitnessTracker/FitnessTracker/Session/SessionRunner.swift \
        FitnessTracker/FitnessTracker/Features/Session/SessionContainerView.swift \
        FitnessTracker/FitnessTrackerTests/SessionRunnerTests.swift
git commit -m "Fire MemoryKeeperCoordinator from SessionRunner.finish() as a non-blocking background call"
```

---

## Task 6: Home "pending observation" review card

**Files:**
- Create: `Features/Home/PendingObservationCard.swift`
- Modify: `Features/Home/HomeView.swift`

**Interfaces:**
- Consumes: `ObservationModel` (`confirmed == false` rows).
- Produces: a SwiftUI view inserted into `HomeView.body`, no new public API
  consumed elsewhere.

- [ ] **Step 1: Create `PendingObservationCard.swift`**

Follows the existing card style in `HomeView.swift` (`bodyWeightCard`,
`streakCard` — check that file's actual styling tokens, e.g. `GymTheme`,
before matching):

```swift
import SwiftUI
import SwiftData

/// One AI-derived, unconfirmed `ObservationModel` awaiting your review
/// (design spec §7). Accept flips `confirmed = true` in place; Dismiss
/// deletes the row outright — there is no "reject but keep" state, since a
/// rejected reading has no value to retain.
struct PendingObservationCard: View {
    let observation: ObservationModel
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Coach noticed")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(formattedValue) \(observation.unit) — \(displayKind)")
                .font(.headline)
            HStack(spacing: 12) {
                Button("Confirm", action: onAccept)
                    .buttonStyle(.borderedProminent)
                Button("Dismiss", role: .destructive, action: onDismiss)
                    .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var formattedValue: String {
        observation.value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", observation.value)
            : String(format: "%.1f", observation.value)
    }

    private var displayKind: String {
        switch observation.kind {
        case "bodyFatPercent": "Body fat"
        case "muscleMassKg": "Muscle mass"
        case "bodyweight": "Bodyweight"
        default: observation.kind
        }
    }
}
```

**Note for the implementer:** if `HomeView.swift` uses `GymTheme.card`/
similar background/corner-radius tokens instead of the raw
`Color(.secondarySystemBackground)`/`RoundedRectangle` above, match those
tokens instead — open `bodyWeightCard`'s implementation first and mirror its
actual styling calls so this card doesn't look inconsistent with the rest of
Home.

- [ ] **Step 2: Wire it into `HomeView`**

In `HomeView.swift`, add the query and insert the card(s) at the top of the
main `VStack`, above `weekStripCard`:

```swift
@Query(filter: #Predicate<ObservationModel> { !$0.confirmed })
private var pendingObservations: [ObservationModel]
```

**Note for the implementer:** this project has a documented, real footgun
with boolean `#Predicate` filters thrashing CoreData's SQL generator (see
`SessionContainerView.swift`'s comment on `activeProviderProfile` and
`docs/HANDOFF.md` for the Settings/Providers hang this caused previously).
`!$0.confirmed` is the same shape as the predicate that caused that hang.
**Do not use the `#Predicate` form above as written** — instead query all
observations unfiltered and filter in Swift, exactly like
`SessionContainerView.activeProviderProfile` does:

```swift
@Query private var allObservations: [ObservationModel]
private var pendingObservations: [ObservationModel] {
    allObservations.filter { !$0.confirmed }
}
```

Then in `body`, inside the outer `VStack(spacing: 16)`, right after
`headerSection`:

```swift
var body: some View {
    ScrollView {
        VStack(spacing: 16) {
            headerSection

            ForEach(pendingObservations) { observation in
                PendingObservationCard(
                    observation: observation,
                    onAccept: { observation.confirmed = true; try? context.save() },
                    onDismiss: { context.delete(observation); try? context.save() }
                )
            }

            weekStripCard
            bodyWeightCard
            streakCard
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 90)
    }
    .background(GymTheme.bg.ignoresSafeArea())
    .onAppear { seedInitialDataIfNeeded() }
    .sheet(item: $activeSheet) { sheet in
        // ... unchanged
    }
}
```

**Note for the implementer:** `ObservationModel` needs `Identifiable` for
`ForEach(pendingObservations)` to compile without an explicit `id:` — SwiftData
`@Model` classes are `Identifiable` via their `persistentModelID` by default,
so this should already work; if it doesn't, add `id: \.persistentModelID` to
the `ForEach` call instead of adding conformance to the model.

- [ ] **Step 3: Build**

Run: `xcodebuild build -scheme FitnessTracker -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' -project FitnessTracker/FitnessTracker.xcodeproj 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`. This task has no dedicated unit tests (a
pure SwiftUI view over a `@Query`) — the coordinator's own write path (Task
4) already verifies `confirmed = false` rows get created; this task only
proves they compile into a working card.

- [ ] **Step 4: Full test run**

Run: `xcodebuild test -scheme FitnessTracker -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' -project FitnessTracker/FitnessTracker.xcodeproj 2>&1 | tail -30`
Expected: green — this is the plan's final verification pass.

- [ ] **Step 5: Commit**

```bash
git add FitnessTracker/FitnessTracker/Features/Home/PendingObservationCard.swift \
        FitnessTracker/FitnessTracker/Features/Home/HomeView.swift
git commit -m "Add Home card to review AI-derived measurement observations"
```

---

## Self-Review Notes

- **Placeholder scan**: every step has real code; the two "Note for the
  implementer" flags (Task 5 Step 4's `SpyKeeper` isolation, Task 6 Step 1's
  exact styling tokens) are genuine ambiguities this brief can't resolve
  without the implementer having the actual file open — not vague hand-waving.
- **Known footgun flagged, not hidden**: Task 6 Step 2 deliberately shows a
  boolean `#Predicate` first, then explicitly says not to use it and gives
  the correct `@Query` + Swift-filter form — this project has hit this exact
  bug twice already (Settings/Root, Settings/Providers), so it's called out
  rather than risk a third occurrence.
- **Scope**: this plan builds the session-end trigger, the consolidation/
  guardrail wiring, and the review card only. The nightly batch trigger, Ask
  Coach as a second trigger, `MemoryOutcome` closing the loop, and wiring
  `MemoryRecall` into plan generation are explicitly out (design doc §10) —
  each is its own future plan.

---

## Execution

Two ways to run this:

1. **Subagent-driven** (recommended) — `superpowers:subagent-driven-development`:
   fresh implementer subagent per task, task review after each, broad review
   at the end.
2. **Inline** — `superpowers:executing-plans`: execute tasks in this session,
   same build-then-test-then-report loop used for the finalize plan.

Given the size (6 tasks, mirrors the finalize plan's granularity), either
works — say which you want.
