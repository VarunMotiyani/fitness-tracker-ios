# Suggestion Cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the generic suggestion-card system (design spec §3's long-promised
"one reusable component ... used for coverage gaps, substitutions ... and anything
Ask Coach proposes") and wire two producers into it: Ask Coach chat proposing an
exercise swap or set/rep/load change to an upcoming session, and a deterministic
coverage-gap detector that runs after plan generation.

**Architecture:** `PendingCoachSuggestion` (new SwiftData model) is the single
queue both producers write to and the Home card reads from. `SuggestionApplier`
is the one deterministic mutation path (decode `StoredPlan` → rebuild the target
`PlannedSession`'s `items` → re-encode) both Accept flows go through. Two new
`CoachTool`s (`propose_exercise_swap`, `propose_set_change`) plus a new read tool
(`get_upcoming_sessions`) extend `AskCoachCoordinator`'s existing toolset.
`CoverageGapDetector` is pure deterministic Swift (no LLM call), reusing
`MuscleBalanceModel.rankOf` — the same computation `AskCoachCoordinator` already
performs for its `get_muscle_balance` tool.

**Tech Stack:** Swift 6 `.v6`, Xcode 26, iOS 26, SwiftData, SwiftUI, Swift
Testing, `FitnessCore` local package (`FitnessDomain`, `Metrics`, `ExerciseCatalog`, `LLMKit`).

**Spec:** `docs/specs/2026-09-05-suggestion-cards-design.md` (all sections,
including §2's rulings — these were decided without a user round-trip per
explicit instruction and are binding).

## Global Constraints

- Xcode 26 default actor isolation is `@MainActor` for the app module.
- Every propose-tool call writes at most one `PendingCoachSuggestion` row; it
  never mutates a `PlannedSession` directly — only `SuggestionApplier.apply`
  (triggered by a user's Accept tap) ever changes plan content, matching "the
  model never writes directly."
- Home reads pending suggestions via `@Query` + Swift-side `.filter { $0.resolvedAt
  == nil }` — **never** a boolean `#Predicate` (this project has hit that exact
  CoreData hang twice already; see `docs/HANDOFF.md`).
- Plain commits, no `Co-Authored-By` trailer. Do not commit/push without being
  asked — however, given the standing instruction to complete this end-to-end
  autonomously, commits from the subagent-driven build process itself are
  expected and should proceed without an extra confirmation per task.
- No real network in any test.
- End state: `xcodebuild test -scheme FitnessTracker -destination
  'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' -project
  FitnessTracker/FitnessTracker.xcodeproj 2>&1 | tail -30` green.

---

## File Structure

- `Models/PendingCoachSuggestion.swift` — **create**.
- `AI/SuggestionApplier.swift` — **create**.
- `AI/Tools/SuggestionTools.swift` — **create**: `ProposeExerciseSwapTool`,
  `ProposeSetChangeTool`, `GetUpcomingSessionsTool`.
- `AI/AskCoachCoordinator.swift` — modify: wire the 3 new tools into
  `buildTools()`.
- `AI/AskCoachPromptBuilder.swift` — modify: add the propose-tools paragraph.
- `Metrics/CoverageGapDetector.swift` (app target, not FitnessCore — it needs
  `ModelContext`) — **create**.
- `AI/PlanGeneration.swift` — modify: call `CoverageGapDetector.detect` after a
  plan is stored.
- `Features/Home/SuggestionCard.swift` — **create**.
- `Features/Home/HomeView.swift` — modify: query + render pending suggestions.
- `FitnessTrackerApp.swift` — modify: register `PendingCoachSuggestion`.
- Tests: `PendingCoachSuggestionTests.swift`, `SuggestionApplierTests.swift`,
  `SuggestionToolsTests.swift`, `CoverageGapDetectorTests.swift` — create.

---

## Task 1: `PendingCoachSuggestion` model

**Files:**
- Create: `Models/PendingCoachSuggestion.swift`
- Modify: `FitnessTrackerApp.swift`
- Test: `FitnessTrackerTests/PendingCoachSuggestionTests.swift`

- [ ] **Step 1: Implement**

```swift
import Foundation
import SwiftData

/// A proposed change to one not-yet-started `PlannedSession`, awaiting your
/// Accept/Skip (design spec §3). `kind` is `"exerciseSwap"`, `"setChange"`, or
/// `"addExercise"` (the coverage-gap detector's kind — inserts a new item
/// rather than modifying one). `resolvedAt == nil` means still pending.
@Model
final class PendingCoachSuggestion {
    var id: UUID
    var plannedSessionID: UUID
    var kind: String
    var exerciseID: String
    var replacementExerciseID: String?
    var targetSets: Int?
    var targetRepsMin: Int?
    var targetRepsMax: Int?
    var targetLoadKg: Double?
    var rationale: String
    var source: String
    var createdAt: Date
    var resolvedAt: Date?
    var accepted: Bool?

    init(plannedSessionID: UUID, kind: String, exerciseID: String, rationale: String, source: String) {
        self.id = UUID()
        self.plannedSessionID = plannedSessionID
        self.kind = kind
        self.exerciseID = exerciseID
        self.replacementExerciseID = nil
        self.targetSets = nil
        self.targetRepsMin = nil
        self.targetRepsMax = nil
        self.targetLoadKg = nil
        self.rationale = rationale
        self.source = source
        self.createdAt = .now
        self.resolvedAt = nil
        self.accepted = nil
    }
}
```

Register `PendingCoachSuggestion.self` in `FitnessTrackerApp.swift`'s
`.modelContainer(for: [...])` list.

- [ ] **Step 2: Test**

```swift
import Testing
import SwiftData
@testable import FitnessTracker

@Suite struct PendingCoachSuggestionTests {
    @Test func defaultsAndRoundTrips() throws {
        let container = try ModelContainer(for: PendingCoachSuggestion.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let s = PendingCoachSuggestion(plannedSessionID: UUID(), kind: "exerciseSwap",
                                       exerciseID: "bench", rationale: "test", source: "askCoach")
        ctx.insert(s)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<PendingCoachSuggestion>())
        #expect(fetched.count == 1)
        #expect(fetched[0].resolvedAt == nil)
        #expect(fetched[0].accepted == nil)
    }
}
```

- [ ] **Step 3: Build and test, then commit**

Run: `xcodebuild test -scheme FitnessTracker -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' -project FitnessTracker/FitnessTracker.xcodeproj -only-testing:FitnessTrackerTests/PendingCoachSuggestionTests 2>&1 | tail -20`

```bash
git add FitnessTracker/FitnessTracker/Models/PendingCoachSuggestion.swift \
        FitnessTracker/FitnessTracker/FitnessTrackerApp.swift \
        FitnessTracker/FitnessTrackerTests/PendingCoachSuggestionTests.swift
git commit -m "Add PendingCoachSuggestion model"
```

---

## Task 2: `SuggestionApplier`

**Files:**
- Create: `AI/SuggestionApplier.swift`
- Test: `FitnessTrackerTests/SuggestionApplierTests.swift`

**Interfaces:**
- Produces: `@MainActor enum SuggestionApplier { static func apply(_ suggestion:
  PendingCoachSuggestion, storedPlan: StoredPlan) throws; static func skip(_
  suggestion: PendingCoachSuggestion) }` — consumed by Task 6's `SuggestionCard`.

- [ ] **Step 1: Write the failing tests**

Build a `WeeklyPlan` with one session/item, encode into a `StoredPlan`, apply a
swap suggestion, decode again, assert the item's `exerciseID` changed and
`wasSwappedFrom`-style provenance isn't needed here (this is the *planned*
item, not a completed entry — no provenance field exists on `PlannedItem`).
Also test a `setChange` suggestion only overriding the fields that are non-nil
(others keep the original item's values), an `addExercise` suggestion
appending a new `PlannedItem`, and `skip` leaving `planJSON` untouched while
setting `resolvedAt`/`accepted = false`.

```swift
import Testing
import Foundation
import FitnessDomain
@testable import FitnessTracker

@Suite struct SuggestionApplierTests {
    private func plan(sessionID: UUID) -> WeeklyPlan {
        WeeklyPlan(weekStartDate: Date(), source: .ruleEngine, rationale: "test",
                  sessions: [PlannedSession(id: sessionID, order: 0, focusMuscles: [.chest], items: [
                      PlannedItem(exerciseID: "bench", targetSets: 3, targetReps: RepRange(min: 6, max: 8),
                                  targetLoadKg: 60, restSeconds: 90, coachNote: "")
                  ])],
                  weeklyVolumeTargets: [])
    }

    @Test func applySwapReplacesExerciseID() throws {
        let sessionID = UUID()
        let stored = try StoredPlan(plan: plan(sessionID: sessionID), hadValidationIssues: false)
        let suggestion = PendingCoachSuggestion(plannedSessionID: sessionID, kind: "exerciseSwap",
                                                exerciseID: "bench", rationale: "test", source: "askCoach")
        suggestion.replacementExerciseID = "incline_bench"

        try SuggestionApplier.apply(suggestion, storedPlan: stored)

        let updated = try stored.decodedPlan()
        #expect(updated.sessions[0].items[0].exerciseID == "incline_bench")
        #expect(suggestion.resolvedAt != nil)
        #expect(suggestion.accepted == true)
    }

    @Test func applySetChangeOverridesOnlyGivenFields() throws {
        let sessionID = UUID()
        let stored = try StoredPlan(plan: plan(sessionID: sessionID), hadValidationIssues: false)
        let suggestion = PendingCoachSuggestion(plannedSessionID: sessionID, kind: "setChange",
                                                exerciseID: "bench", rationale: "test", source: "askCoach")
        suggestion.targetSets = 4

        try SuggestionApplier.apply(suggestion, storedPlan: stored)

        let updated = try stored.decodedPlan()
        let item = updated.sessions[0].items[0]
        #expect(item.targetSets == 4)
        #expect(item.targetLoadKg == 60) // unchanged
        #expect(item.targetReps.min == 6) // unchanged
    }

    @Test func applyAddExerciseAppendsNewItem() throws {
        let sessionID = UUID()
        let stored = try StoredPlan(plan: plan(sessionID: sessionID), hadValidationIssues: false)
        let suggestion = PendingCoachSuggestion(plannedSessionID: sessionID, kind: "addExercise",
                                                exerciseID: "lateral_raise", rationale: "test", source: "coverageGap")
        suggestion.targetSets = 3

        try SuggestionApplier.apply(suggestion, storedPlan: stored)

        let updated = try stored.decodedPlan()
        #expect(updated.sessions[0].items.count == 2)
        #expect(updated.sessions[0].items.last?.exerciseID == "lateral_raise")
    }

    @Test func skipLeavesPlanUntouched() {
        let suggestion = PendingCoachSuggestion(plannedSessionID: UUID(), kind: "exerciseSwap",
                                                exerciseID: "bench", rationale: "test", source: "askCoach")
        SuggestionApplier.skip(suggestion)
        #expect(suggestion.resolvedAt != nil)
        #expect(suggestion.accepted == false)
    }

    @Test func applyThrowsForUnknownSession() {
        let stored = try! StoredPlan(plan: plan(sessionID: UUID()), hadValidationIssues: false)
        let suggestion = PendingCoachSuggestion(plannedSessionID: UUID(), kind: "exerciseSwap",
                                                exerciseID: "bench", rationale: "test", source: "askCoach")
        suggestion.replacementExerciseID = "incline_bench"
        #expect(throws: (any Error).self) {
            try SuggestionApplier.apply(suggestion, storedPlan: stored)
        }
    }
}
```

**Note for the implementer:** check `WeeklyPlan.init`'s real `PlanSource` enum
case names (`.ruleEngine` is a guess — verify against
`FitnessCore/Sources/FitnessDomain/WeeklyPlan.swift` or wherever `PlanSource`
is declared) before trusting the test fixture verbatim.

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme FitnessTracker -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' -project FitnessTracker/FitnessTracker.xcodeproj -only-testing:FitnessTrackerTests/SuggestionApplierTests 2>&1 | tail -30`

- [ ] **Step 3: Implement**

```swift
import Foundation
import FitnessDomain

enum SuggestionApplierError: Error {
    case sessionNotFound
}

@MainActor
enum SuggestionApplier {
    static func apply(_ suggestion: PendingCoachSuggestion, storedPlan: StoredPlan) throws {
        let plan = try storedPlan.decodedPlan()
        guard let sessionIndex = plan.sessions.firstIndex(where: { $0.id == suggestion.plannedSessionID }) else {
            throw SuggestionApplierError.sessionNotFound
        }
        let session = plan.sessions[sessionIndex]
        var items = session.items

        switch suggestion.kind {
        case "exerciseSwap":
            if let idx = items.firstIndex(where: { $0.exerciseID == suggestion.exerciseID }),
               let replacement = suggestion.replacementExerciseID {
                let old = items[idx]
                items[idx] = PlannedItem(exerciseID: replacement, targetSets: old.targetSets,
                                         targetReps: old.targetReps, targetLoadKg: old.targetLoadKg,
                                         restSeconds: old.restSeconds, coachNote: old.coachNote)
            }
        case "setChange":
            if let idx = items.firstIndex(where: { $0.exerciseID == suggestion.exerciseID }) {
                let old = items[idx]
                let repRange = (suggestion.targetRepsMin != nil || suggestion.targetRepsMax != nil)
                    ? RepRange(min: suggestion.targetRepsMin ?? old.targetReps.min,
                              max: suggestion.targetRepsMax ?? old.targetReps.max)
                    : old.targetReps
                items[idx] = PlannedItem(exerciseID: old.exerciseID,
                                         targetSets: suggestion.targetSets ?? old.targetSets,
                                         targetReps: repRange,
                                         targetLoadKg: suggestion.targetLoadKg ?? old.targetLoadKg,
                                         restSeconds: old.restSeconds, coachNote: old.coachNote)
            }
        case "addExercise":
            items.append(PlannedItem(exerciseID: suggestion.exerciseID,
                                     targetSets: suggestion.targetSets ?? 3,
                                     targetReps: RepRange(min: suggestion.targetRepsMin ?? 8, max: suggestion.targetRepsMax ?? 12),
                                     targetLoadKg: suggestion.targetLoadKg, restSeconds: 90, coachNote: ""))
        default:
            break
        }

        let updatedSession = PlannedSession(id: session.id, order: session.order,
                                            focusMuscles: session.focusMuscles, items: items)
        var sessions = plan.sessions
        sessions[sessionIndex] = updatedSession
        let updatedPlan = WeeklyPlan(weekStartDate: plan.weekStartDate, source: plan.source,
                                     rationale: plan.rationale, sessions: sessions,
                                     weeklyVolumeTargets: plan.weeklyVolumeTargets)
        storedPlan.planJSON = try JSONEncoder().encode(updatedPlan)

        suggestion.resolvedAt = .now
        suggestion.accepted = true
    }

    static func skip(_ suggestion: PendingCoachSuggestion) {
        suggestion.resolvedAt = .now
        suggestion.accepted = false
    }
}
```

**Note for the implementer:** verify `StoredPlan.planJSON`'s access level (it's
declared in the same app target, should be assignable) and `WeeklyPlan`/
`PlannedSession`/`PlannedItem`'s exact `init` parameter names against real
source before trusting this verbatim — the memory-keeper and Ask Coach plans
both caught real signature mismatches this way.

- [ ] **Step 4: Run tests to verify they pass, then commit**

```bash
git add FitnessTracker/FitnessTracker/AI/SuggestionApplier.swift \
        FitnessTracker/FitnessTrackerTests/SuggestionApplierTests.swift
git commit -m "Add SuggestionApplier: deterministic mutation for accepted suggestions"
```

---

## Task 3: Suggestion tools for Ask Coach

**Files:**
- Create: `AI/Tools/SuggestionTools.swift`
- Test: `FitnessTrackerTests/SuggestionToolsTests.swift`

**Interfaces:**
- Consumes: `PendingCoachSuggestion` (Task 1), `CoachTool`/`ToolDescriptor`
  (existing).
- Produces: `ProposeExerciseSwapTool`, `ProposeSetChangeTool`,
  `GetUpcomingSessionsTool` (all `@MainActor`, `ModelContext`-holding) —
  consumed by Task 4's `AskCoachCoordinator.buildTools()`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import SwiftData
import Foundation
import FitnessDomain
import ExerciseCatalog
@testable import FitnessTracker

@MainActor
@Suite struct SuggestionToolsTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: StoredPlan.self, PendingCoachSuggestion.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func exercise(_ id: String) -> Exercise {
        Exercise(id: id, name: id, primaryMuscle: .chest, secondaryMuscles: [],
                 equipment: .barbell, mechanic: .compound, force: .push,
                 difficulty: .intermediate, isUnilateral: false, instructions: [], imagePaths: [])
    }

    private func catalog() -> CatalogStore { CatalogStore(exercises: [exercise("bench"), exercise("incline_bench")]) }

    private func seedPlan(in ctx: ModelContext) throws -> UUID {
        let sessionID = UUID()
        let plan = WeeklyPlan(weekStartDate: Date(), source: .ruleEngine, rationale: "test",
                              sessions: [PlannedSession(id: sessionID, order: 0, focusMuscles: [.chest], items: [
                                  PlannedItem(exerciseID: "bench", targetSets: 3, targetReps: RepRange(min: 6, max: 8),
                                              targetLoadKg: 60, restSeconds: 90, coachNote: "")
                              ])], weeklyVolumeTargets: [])
        let stored = try StoredPlan(plan: plan, hadValidationIssues: false)
        ctx.insert(stored)
        try ctx.save()
        return sessionID
    }

    @Test func proposeExerciseSwapWritesPendingSuggestion() throws {
        let ctx = ModelContext(try container())
        let sessionID = try seedPlan(in: ctx)
        let tool = ProposeExerciseSwapTool(context: ctx, catalog: catalog())

        let args = "{\"plannedSessionID\": \"\(sessionID.uuidString)\", \"exerciseID\": \"bench\", \"replacementExerciseID\": \"incline_bench\", \"rationale\": \"shoulder discomfort\"}"
        let result = tool.run(argsJSON: args)

        #expect(!result.contains("error"))
        let pending = try ctx.fetch(FetchDescriptor<PendingCoachSuggestion>())
        #expect(pending.count == 1)
        #expect(pending[0].kind == "exerciseSwap")
        #expect(pending[0].replacementExerciseID == "incline_bench")
    }

    @Test func proposeExerciseSwapRejectsUnknownReplacementExercise() throws {
        let ctx = ModelContext(try container())
        let sessionID = try seedPlan(in: ctx)
        let tool = ProposeExerciseSwapTool(context: ctx, catalog: catalog())

        let args = "{\"plannedSessionID\": \"\(sessionID.uuidString)\", \"exerciseID\": \"bench\", \"replacementExerciseID\": \"nonexistent\", \"rationale\": \"test\"}"
        let result = tool.run(argsJSON: args)

        #expect(result.contains("error"))
        #expect(try ctx.fetch(FetchDescriptor<PendingCoachSuggestion>()).isEmpty)
    }

    @Test func proposeSetChangeWritesPendingSuggestion() throws {
        let ctx = ModelContext(try container())
        let sessionID = try seedPlan(in: ctx)
        let tool = ProposeSetChangeTool(context: ctx)

        let args = "{\"plannedSessionID\": \"\(sessionID.uuidString)\", \"exerciseID\": \"bench\", \"targetSets\": 4, \"rationale\": \"add volume\"}"
        let result = tool.run(argsJSON: args)

        #expect(!result.contains("error"))
        let pending = try ctx.fetch(FetchDescriptor<PendingCoachSuggestion>())
        #expect(pending[0].targetSets == 4)
    }

    @Test func proposeSetChangeRejectsImplausibleSets() throws {
        let ctx = ModelContext(try container())
        let sessionID = try seedPlan(in: ctx)
        let tool = ProposeSetChangeTool(context: ctx)

        let args = "{\"plannedSessionID\": \"\(sessionID.uuidString)\", \"exerciseID\": \"bench\", \"targetSets\": 99, \"rationale\": \"test\"}"
        let result = tool.run(argsJSON: args)

        #expect(result.contains("error"))
    }

    @Test func getUpcomingSessionsListsCurrentPlan() throws {
        let ctx = ModelContext(try container())
        _ = try seedPlan(in: ctx)
        let tool = GetUpcomingSessionsTool(context: ctx, catalog: catalog())

        let result = tool.run(argsJSON: "{}")

        #expect(result.contains("bench"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme FitnessTracker -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' -project FitnessTracker/FitnessTracker.xcodeproj -only-testing:FitnessTrackerTests/SuggestionToolsTests 2>&1 | tail -30`

- [ ] **Step 3: Implement `AI/Tools/SuggestionTools.swift`**

```swift
import Foundation
import SwiftData
import FitnessDomain
import ExerciseCatalog

private func mostRecentStoredPlan(in context: ModelContext) -> StoredPlan? {
    (try? context.fetch(FetchDescriptor<StoredPlan>(sortBy: [SortDescriptor(\.generatedAt, order: .reverse)])))?.first
}

struct ProposeExerciseSwapArgs: Decodable {
    let plannedSessionID: String
    let exerciseID: String
    let replacementExerciseID: String
    let rationale: String
}

/// Writes a `PendingCoachSuggestion`, never mutates the plan directly — only
/// your Accept tap (via `SuggestionApplier`) does that (design spec §4).
@MainActor
struct ProposeExerciseSwapTool: CoachTool {
    let context: ModelContext
    let catalog: CatalogStore

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            name: "propose_exercise_swap",
            description: "Propose swapping one exercise for another in an upcoming (not yet started) session. Use get_upcoming_sessions first to find the right plannedSessionID.",
            argsSchemaJSON: "{\"plannedSessionID\": \"string\", \"exerciseID\": \"string\", \"replacementExerciseID\": \"string\", \"rationale\": \"string\"}"
        )
    }

    func run(argsJSON: String) -> String {
        guard let args = decodeArgs(argsJSON, as: ProposeExerciseSwapArgs.self),
              let sessionID = UUID(uuidString: args.plannedSessionID)
        else { return "{\"error\": \"bad args\"}" }
        guard catalog.exercise(id: args.replacementExerciseID) != nil else {
            return "{\"error\": \"unknown replacement exercise\"}"
        }
        guard let plan = mostRecentStoredPlan(in: context)?.decodedPlanOrNil(),
              plan.sessions.contains(where: { $0.id == sessionID })
        else { return "{\"error\": \"unknown session\"}" }

        let suggestion = PendingCoachSuggestion(plannedSessionID: sessionID, kind: "exerciseSwap",
                                                exerciseID: args.exerciseID, rationale: args.rationale, source: "askCoach")
        suggestion.replacementExerciseID = args.replacementExerciseID
        context.insert(suggestion)
        try? context.save()
        return "{\"status\": \"proposed\"}"
    }
}

struct ProposeSetChangeArgs: Decodable {
    let plannedSessionID: String
    let exerciseID: String
    let targetSets: Int?
    let targetRepsMin: Int?
    let targetRepsMax: Int?
    let targetLoadKg: Double?
    let rationale: String
}

@MainActor
struct ProposeSetChangeTool: CoachTool {
    let context: ModelContext

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            name: "propose_set_change",
            description: "Propose changing sets/reps/load for one exercise in an upcoming session. Omit any field you're not changing.",
            argsSchemaJSON: "{\"plannedSessionID\": \"string\", \"exerciseID\": \"string\", \"targetSets\": \"number?\", \"targetRepsMin\": \"number?\", \"targetRepsMax\": \"number?\", \"targetLoadKg\": \"number?\", \"rationale\": \"string\"}"
        )
    }

    func run(argsJSON: String) -> String {
        guard let args = decodeArgs(argsJSON, as: ProposeSetChangeArgs.self),
              let sessionID = UUID(uuidString: args.plannedSessionID)
        else { return "{\"error\": \"bad args\"}" }
        if let sets = args.targetSets, !(1...10).contains(sets) { return "{\"error\": \"implausible sets\"}" }
        if let reps = args.targetRepsMax, !(1...30).contains(reps) { return "{\"error\": \"implausible reps\"}" }
        if let load = args.targetLoadKg, !(0...500).contains(load) { return "{\"error\": \"implausible load\"}" }

        let suggestion = PendingCoachSuggestion(plannedSessionID: sessionID, kind: "setChange",
                                                exerciseID: args.exerciseID, rationale: args.rationale, source: "askCoach")
        suggestion.targetSets = args.targetSets
        suggestion.targetRepsMin = args.targetRepsMin
        suggestion.targetRepsMax = args.targetRepsMax
        suggestion.targetLoadKg = args.targetLoadKg
        context.insert(suggestion)
        try? context.save()
        return "{\"status\": \"proposed\"}"
    }
}

@MainActor
struct GetUpcomingSessionsTool: CoachTool {
    let context: ModelContext
    let catalog: CatalogStore

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            name: "get_upcoming_sessions",
            description: "Lists this week's planned sessions (id, focus muscles, exercises) so you can find the plannedSessionID for a propose_* call.",
            argsSchemaJSON: "{}"
        )
    }

    func run(argsJSON: String) -> String {
        guard let plan = mostRecentStoredPlan(in: context)?.decodedPlanOrNil() else {
            return "{\"error\": \"no plan\"}"
        }
        let payload = plan.sessions.map { session -> [String: Any] in
            [
                "plannedSessionID": session.id.uuidString,
                "focusMuscles": session.focusMuscles.map(\.rawValue),
                "exercises": session.items.map { catalog.exercise(id: $0.exerciseID)?.name ?? $0.exerciseID }
            ]
        }
        return encodeJSONObject(["sessions": payload])
    }
}

extension StoredPlan {
    func decodedPlanOrNil() -> WeeklyPlan? { try? decodedPlan() }
}
```

**Note for the implementer:** verify `encodeJSONObject` (from `AI/Tools/CoachTool.swift`) accepts
`[String: Any]` with a nested array-of-dictionaries value the way it's used
here — check its real implementation before trusting this verbatim.

- [ ] **Step 4: Run tests to verify they pass, then commit**

```bash
git add FitnessTracker/FitnessTracker/AI/Tools/SuggestionTools.swift \
        FitnessTracker/FitnessTrackerTests/SuggestionToolsTests.swift
git commit -m "Add ProposeExerciseSwapTool, ProposeSetChangeTool, GetUpcomingSessionsTool"
```

---

## Task 4: Wire the new tools into `AskCoachCoordinator`

**Files:**
- Modify: `AI/AskCoachCoordinator.swift`
- Modify: `AI/AskCoachPromptBuilder.swift`
- Modify (extend): `FitnessTrackerTests/AskCoachCoordinatorTests.swift`,
  `FitnessTrackerTests/AskCoachPromptBuilderTests.swift`

- [ ] **Step 1: Extend `buildTools()`**

In `AskCoachCoordinator.swift`, add the 3 new tools to the array `buildTools()`
returns:

```swift
return [
    GetRecoveryStatusTool(statuses: recoveryStatuses),
    GetMuscleBalanceTool(load: load),
    QueryTrainingDataTool(exportJSON: exportJSON),
    ProposeExerciseSwapTool(context: context, catalog: catalog),
    ProposeSetChangeTool(context: context),
    GetUpcomingSessionsTool(context: context, catalog: catalog)
]
```

- [ ] **Step 2: Extend `AskCoachPromptBuilder.system()`**

Add one paragraph after the existing "cannot change their program" sentence,
replacing that sentence's absolute claim (it's no longer true):

```swift
"""
... (existing persona intro) ...

You now have tools to propose a concrete change to an UPCOMING session (one
that hasn't started yet): propose_exercise_swap and propose_set_change. Use
get_upcoming_sessions first to find the right plannedSessionID — never guess
one. Every proposal becomes a card the athlete taps to accept or skip; you
never change anything directly. If they're asking about the session they're
currently in, tell them to use the swap/adjust controls in the session screen
instead — your proposals can only reach a session that hasn't started.

If a request is ambiguous, ask a clarifying question rather than guessing what
they meant. Keep replies conversational and concise — this is a chat, not a
report. Respond only in the required JSON shape.
"""
```

- [ ] **Step 3: Add a test proving the new tools are registered**

In `AskCoachCoordinatorTests.swift`, add a test scripting a `propose_exercise_swap`
tool-call turn followed by a final turn, asserting a `PendingCoachSuggestion`
row exists after `send` returns — mirroring the existing
`sendPersistsBothMessagesAndReturnsReply` test's setup but with a
`{"decision":"tool_call","toolCall":{"name":"propose_exercise_swap","argsJSON":"..."}}`
first turn (needs a seeded `StoredPlan` in the test's container, matching
`SuggestionToolsTests`' `seedPlan` helper — copy or share that pattern).

- [ ] **Step 4: Run full suite, then commit**

```bash
git add FitnessTracker/FitnessTracker/AI/AskCoachCoordinator.swift \
        FitnessTracker/FitnessTracker/AI/AskCoachPromptBuilder.swift \
        FitnessTracker/FitnessTrackerTests/AskCoachCoordinatorTests.swift
git commit -m "Wire propose_exercise_swap/propose_set_change/get_upcoming_sessions into AskCoachCoordinator"
```

---

## Task 5: `CoverageGapDetector`

**Files:**
- Create: `Metrics/CoverageGapDetector.swift`
- Modify: `AI/PlanGeneration.swift`
- Test: `FitnessTrackerTests/CoverageGapDetectorTests.swift`

**Interfaces:**
- Produces: `@MainActor enum CoverageGapDetector { static func detect(context:
  ModelContext, catalog: CatalogStore, storedPlan: StoredPlan) }` — called from
  `generateAndStore` right after a plan is stored.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import SwiftData
import Foundation
import FitnessDomain
import ExerciseCatalog
@testable import FitnessTracker

@MainActor
@Suite struct CoverageGapDetectorTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: StoredPlan.self, PendingCoachSuggestion.self,
                           CompletedSessionModel.self, CompletedEntryModel.self, LoggedSetModel.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func exercise(_ id: String, primary: MuscleGroup) -> Exercise {
        Exercise(id: id, name: id, primaryMuscle: primary, secondaryMuscles: [],
                 equipment: .barbell, mechanic: .compound, force: .push,
                 difficulty: .intermediate, isUnilateral: false, instructions: [], imagePaths: [])
    }

    private func catalog() -> CatalogStore {
        CatalogStore(exercises: [exercise("bench", primary: .chest), exercise("lateral_raise", primary: .shoulders)])
    }

    @Test func proposesAddExerciseForAMissedMuscle() throws {
        let ctx = ModelContext(try container())
        let sessionID = UUID()
        let plan = WeeklyPlan(weekStartDate: Date(), source: .ruleEngine, rationale: "test",
                              sessions: [PlannedSession(id: sessionID, order: 0, focusMuscles: [.chest, .shoulders], items: [
                                  PlannedItem(exerciseID: "bench", targetSets: 3, targetReps: RepRange(min: 6, max: 8),
                                              targetLoadKg: 60, restSeconds: 90, coachNote: "")
                              ])], weeklyVolumeTargets: [])
        let stored = try StoredPlan(plan: plan, hadValidationIssues: false)
        ctx.insert(stored)
        try ctx.save()

        CoverageGapDetector.detect(context: ctx, catalog: catalog(), storedPlan: stored)

        let pending = try ctx.fetch(FetchDescriptor<PendingCoachSuggestion>())
        #expect(pending.contains { $0.kind == "addExercise" })
    }

    @Test func doesNotDuplicateAnUnresolvedSuggestionForTheSameMuscle() throws {
        let ctx = ModelContext(try container())
        let sessionID = UUID()
        let plan = WeeklyPlan(weekStartDate: Date(), source: .ruleEngine, rationale: "test",
                              sessions: [PlannedSession(id: sessionID, order: 0, focusMuscles: [.chest], items: [
                                  PlannedItem(exerciseID: "bench", targetSets: 3, targetReps: RepRange(min: 6, max: 8),
                                              targetLoadKg: 60, restSeconds: 90, coachNote: "")
                              ])], weeklyVolumeTargets: [])
        let stored = try StoredPlan(plan: plan, hadValidationIssues: false)
        ctx.insert(stored)
        try ctx.save()

        CoverageGapDetector.detect(context: ctx, catalog: catalog(), storedPlan: stored)
        let firstCount = try ctx.fetch(FetchDescriptor<PendingCoachSuggestion>()).count
        CoverageGapDetector.detect(context: ctx, catalog: catalog(), storedPlan: stored)
        let secondCount = try ctx.fetch(FetchDescriptor<PendingCoachSuggestion>()).count

        #expect(firstCount == secondCount)
    }
}
```

**Note for the implementer:** verify `PlanSource`'s real case name (`.ruleEngine`
is a guess, same caveat as Task 2) before trusting these fixtures verbatim.

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Implement `Metrics/CoverageGapDetector.swift`**

```swift
import Foundation
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics

/// Deterministic (no LLM call) — proposes adding one exercise for each muscle
/// `MuscleBalanceModel.rankOf` reports as missed this week (design spec §6).
/// Skips a muscle that already has an unresolved pending suggestion for it.
@MainActor
enum CoverageGapDetector {
    static func detect(context: ModelContext, catalog: CatalogStore, storedPlan: StoredPlan) {
        guard let plan = try? storedPlan.decodedPlan(), let firstSession = plan.sessions.first else { return }

        var effectiveSetItems: [MuscleBalanceModel.EffectiveSetItem] = []
        for session in (try? context.fetch(FetchDescriptor<CompletedSessionModel>())) ?? [] {
            for entry in session.entries where !entry.skipped {
                guard let ex = catalog.exercise(id: entry.exerciseID) else { continue }
                let doneSets = entry.sets.filter { !$0.isWarmup }.count
                if doneSets > 0 { effectiveSetItems.append(.init(exercise: ex, sets: doneSets)) }
            }
        }
        let load = MuscleBalanceModel.loadOf(items: effectiveSetItems)
        let (_, missed) = MuscleBalanceModel.rankOf(load: load)

        let slugToMuscle: [String: MuscleGroup] = Dictionary(
            uniqueKeysWithValues: MuscleGroup.allCases.map { (MuscleBalanceModel.canonicalSlug(for: $0), $0) }
        )

        let existingSuggestions = (try? context.fetch(FetchDescriptor<PendingCoachSuggestion>())) ?? []
        let unresolvedExerciseIDs = Set(existingSuggestions.filter { $0.resolvedAt == nil }.map(\.exerciseID))

        for slug in missed {
            guard let muscle = slugToMuscle[slug] else { continue }
            guard let candidate = catalog.exercises.first(where: { $0.primaryMuscle == muscle }) else { continue }
            guard !unresolvedExerciseIDs.contains(candidate.id) else { continue }

            let suggestion = PendingCoachSuggestion(plannedSessionID: firstSession.id, kind: "addExercise",
                                                    exerciseID: candidate.id,
                                                    rationale: "\(muscle.rawValue.capitalized) hasn't been trained this window.",
                                                    source: "coverageGap")
            suggestion.targetSets = 3
            suggestion.targetRepsMin = 8
            suggestion.targetRepsMax = 12
            context.insert(suggestion)
        }
        try? context.save()
    }
}
```

**Note for the implementer:** verify `CatalogStore` exposes an `exercises`
property to iterate (used above as `catalog.exercises.first(where:)`) — check
`ExerciseCatalog`'s real `CatalogStore` API; if it only exposes `exercise(id:)`
lookup, you'll need a different way to find a candidate exercise for a given
`MuscleGroup` (e.g. add an iteration method, or accept an injected candidate
list) — use your judgment and note the adaptation.

- [ ] **Step 4: Wire into `generateAndStore`**

In `AI/PlanGeneration.swift`, after `modelContext.insert(stored)` (the line that
inserts the new `StoredPlan`), add: `CoverageGapDetector.detect(context:
modelContext, catalog: catalog, storedPlan: stored)`.

- [ ] **Step 5: Run tests, full suite, then commit**

```bash
git add FitnessTracker/FitnessTracker/Metrics/CoverageGapDetector.swift \
        FitnessTracker/FitnessTracker/AI/PlanGeneration.swift \
        FitnessTracker/FitnessTrackerTests/CoverageGapDetectorTests.swift
git commit -m "Add CoverageGapDetector: proposes an exercise for each under-trained muscle after plan generation"
```

---

## Task 6: Home UI — `SuggestionCard`

**Files:**
- Create: `Features/Home/SuggestionCard.swift`
- Modify: `Features/Home/HomeView.swift`

- [ ] **Step 1: Implement `SuggestionCard.swift`**

Follow `PendingObservationCard.swift`'s exact visual pattern (built in the
memory-keeper plan) — same `GymTheme` tokens, same Confirm/Dismiss button
shapes. Content: the `rationale` text, a one-line description of the change
(e.g. "Swap Bench Press → Incline Bench Press" or "Add Lateral Raise, 3×8-12"),
Accept and Skip buttons.

```swift
import SwiftUI
import SwiftData

struct SuggestionCard: View {
    let suggestion: PendingCoachSuggestion
    let catalog: CatalogStore
    let onAccept: () -> Void
    let onSkip: () -> Void

    private var summary: String {
        let exerciseName = catalog.exercise(id: suggestion.exerciseID)?.name ?? suggestion.exerciseID
        switch suggestion.kind {
        case "exerciseSwap":
            let replacementName = suggestion.replacementExerciseID.flatMap { catalog.exercise(id: $0)?.name } ?? suggestion.replacementExerciseID ?? "?"
            return "Swap \(exerciseName) → \(replacementName)"
        case "addExercise":
            return "Add \(exerciseName)" + (suggestion.targetSets.map { ", \($0) sets" } ?? "")
        default:
            return "Adjust \(exerciseName)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Coach suggests")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(summary)
                .font(.headline)
            Text(suggestion.rationale)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Accept", action: onAccept)
                    .buttonStyle(.borderedProminent)
                Button("Skip", role: .destructive, action: onSkip)
                    .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}
```

**Note for the implementer:** open `PendingObservationCard.swift` first and
match its actual styling tokens/structure exactly rather than the illustrative
code above if they differ — that file is the established precedent for this
exact card pattern in this codebase.

- [ ] **Step 2: Wire into `HomeView`**

Same `@Query` + Swift-side-filter pattern as `PendingObservationCard`'s wiring
(never a boolean `#Predicate`):

```swift
@Query private var allSuggestions: [PendingCoachSuggestion]
private var pendingSuggestions: [PendingCoachSuggestion] {
    allSuggestions.filter { $0.resolvedAt == nil }
}
```

Render below the pending-observations section, in the same `VStack`:

```swift
ForEach(pendingSuggestions) { suggestion in
    SuggestionCard(
        suggestion: suggestion, catalog: catalog,
        onAccept: {
            if let stored = plans.first {
                try? SuggestionApplier.apply(suggestion, storedPlan: stored)
                try? context.save()
            }
        },
        onSkip: { SuggestionApplier.skip(suggestion); try? context.save() }
    )
}
```

**Note for the implementer:** `HomeView` may already have a `plans`/`StoredPlan`
query in scope from its existing plan-rendering logic — reuse it rather than
adding a duplicate `@Query`. Check the file first.

- [ ] **Step 3: Build, full test run, commit**

```bash
git add FitnessTracker/FitnessTracker/Features/Home/SuggestionCard.swift \
        FitnessTracker/FitnessTracker/Features/Home/HomeView.swift
git commit -m "Add SuggestionCard: Home review UI for Ask Coach and coverage-gap proposals"
```

---

## Self-Review Notes

- **Placeholder scan:** every step has real code; the "Note for the
  implementer" flags are genuine signature-verification points this plan
  cannot resolve without the actual source open (a pattern every plan this
  session has used successfully).
- **Scope:** session-scoped proposals + coverage-gap only. Permanent routine
  revisions (Part 3) and MemoryOutcome wiring are explicitly out, per
  §2/§8 of the spec.

## Execution

Subagent-driven (`superpowers:subagent-driven-development`) — proceed without
further check-ins per standing instruction to complete this end-to-end.
