import Testing
import SwiftData
import Foundation
import FitnessDomain
import ExerciseCatalog
import RuleEngine
@testable import FitnessTracker

@MainActor
@Suite struct CoachActionToolsTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: StoredPlan.self, PendingCoachSuggestion.self, BodyweightEntryModel.self,
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

    // MARK: - start_workout

    @Test func startWorkoutRecordsSessionIDOnTheSink() throws {
        let ctx = ModelContext(try container())
        let sessionID = try seedPlan(in: ctx)
        let sink = CoachActionSink()
        let tool = StartWorkoutTool(context: ctx, sink: sink)

        let result = tool.run(argsJSON: "{\"plannedSessionID\": \"\(sessionID.uuidString)\"}")

        #expect(!result.contains("error"))
        #expect(sink.startSessionID == sessionID)
    }

    @Test func startWorkoutRejectsUnknownSession() throws {
        let ctx = ModelContext(try container())
        _ = try seedPlan(in: ctx)
        let sink = CoachActionSink()
        let tool = StartWorkoutTool(context: ctx, sink: sink)

        let result = tool.run(argsJSON: "{\"plannedSessionID\": \"\(UUID().uuidString)\"}")

        #expect(result.contains("error"))
        #expect(sink.startSessionID == nil)
    }

    // MARK: - regenerate_plan

    @Test func regeneratePlanOnlyFlagsTheSink() {
        let sink = CoachActionSink()
        let tool = RegeneratePlanTool(sink: sink)

        let result = tool.run(argsJSON: "{\"reason\": \"switch to 5 days\"}")

        #expect(!result.contains("error"))
        #expect(sink.requestedPlanRegeneration)
    }

    // MARK: - set_day_to_rest

    @Test func setDayToRestWritesTheOverride() throws {
        let d = UserDefaults.standard
        let key = WorkoutScheduleStore.dayPlanKey
        let saved = d.string(forKey: key)
        defer { d.set(saved, forKey: key) }
        d.removeObject(forKey: key)

        let tool = SetDayToRestTool()
        let result = tool.run(argsJSON: "{\"date\": \"2026-09-15\"}")

        #expect(!result.contains("error"))
        #expect(WorkoutScheduleStore.userDayPlan["2026-09-15"] == "rest")
    }

    @Test func setDayToRestRejectsBadDateFormat() {
        let tool = SetDayToRestTool()
        let result = tool.run(argsJSON: "{\"date\": \"not-a-date\"}")
        #expect(result.contains("error"))
    }

    // MARK: - apply_exercise_swap / apply_set_change (direct, no approval card)

    @Test func applyExerciseSwapMutatesThePlanDirectlyWithNoPendingSuggestion() throws {
        let ctx = ModelContext(try container())
        let sessionID = try seedPlan(in: ctx)
        let tool = ApplyExerciseSwapTool(context: ctx, catalog: catalog())

        let args = "{\"plannedSessionID\": \"\(sessionID.uuidString)\", \"exerciseID\": \"bench\", \"replacementExerciseID\": \"incline_bench\", \"rationale\": \"asked directly\"}"
        let result = tool.run(argsJSON: args)

        #expect(!result.contains("error"))
        // Unlike propose_exercise_swap, nothing is left pending — it's applied.
        #expect(try ctx.fetch(FetchDescriptor<PendingCoachSuggestion>()).isEmpty)
        let plan = try #require(try ctx.fetch(FetchDescriptor<StoredPlan>()).first).decodedPlan()
        #expect(plan.sessions.first?.items.first?.exerciseID == "incline_bench")
    }

    @Test func applyExerciseSwapRejectsUnknownReplacement() throws {
        let ctx = ModelContext(try container())
        let sessionID = try seedPlan(in: ctx)
        let tool = ApplyExerciseSwapTool(context: ctx, catalog: catalog())

        let args = "{\"plannedSessionID\": \"\(sessionID.uuidString)\", \"exerciseID\": \"bench\", \"replacementExerciseID\": \"nonexistent\", \"rationale\": \"x\"}"
        let result = tool.run(argsJSON: args)

        #expect(result.contains("error"))
        let plan = try #require(try ctx.fetch(FetchDescriptor<StoredPlan>()).first).decodedPlan()
        #expect(plan.sessions.first?.items.first?.exerciseID == "bench")
    }

    @Test func applySetChangeMutatesThePlanDirectly() throws {
        let ctx = ModelContext(try container())
        let sessionID = try seedPlan(in: ctx)
        let tool = ApplySetChangeTool(context: ctx)

        let args = "{\"plannedSessionID\": \"\(sessionID.uuidString)\", \"exerciseID\": \"bench\", \"targetSets\": 5, \"rationale\": \"asked directly\"}"
        let result = tool.run(argsJSON: args)

        #expect(!result.contains("error"))
        #expect(try ctx.fetch(FetchDescriptor<PendingCoachSuggestion>()).isEmpty)
        let plan = try #require(try ctx.fetch(FetchDescriptor<StoredPlan>()).first).decodedPlan()
        #expect(plan.sessions.first?.items.first?.targetSets == 5)
    }

    @Test func applySetChangeRejectsImplausibleSets() throws {
        let ctx = ModelContext(try container())
        let sessionID = try seedPlan(in: ctx)
        let tool = ApplySetChangeTool(context: ctx)

        let args = "{\"plannedSessionID\": \"\(sessionID.uuidString)\", \"exerciseID\": \"bench\", \"targetSets\": 99, \"rationale\": \"x\"}"
        let result = tool.run(argsJSON: args)

        #expect(result.contains("error"))
    }

    // MARK: - log_bodyweight

    @Test func logBodyweightWritesAnEntry() throws {
        let ctx = ModelContext(try container())
        let tool = LogBodyweightTool(context: ctx)

        let result = tool.run(argsJSON: "{\"kg\": 76.5}")

        #expect(!result.contains("error"))
        let entries = try ctx.fetch(FetchDescriptor<BodyweightEntryModel>())
        #expect(entries.count == 1)
        #expect(entries.first?.kg == 76.5)
    }

    @Test func logBodyweightRejectsImplausibleWeight() throws {
        let ctx = ModelContext(try container())
        let tool = LogBodyweightTool(context: ctx)

        let result = tool.run(argsJSON: "{\"kg\": 5}")

        #expect(result.contains("error"))
        #expect(try ctx.fetch(FetchDescriptor<BodyweightEntryModel>()).isEmpty)
    }
}
