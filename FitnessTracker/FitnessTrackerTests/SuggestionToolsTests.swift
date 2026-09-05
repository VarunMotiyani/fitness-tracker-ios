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
