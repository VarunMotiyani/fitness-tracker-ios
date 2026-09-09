import Testing
import SwiftData
import Foundation
import FitnessDomain
import ExerciseCatalog
import RuleEngine
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

    @Test func proposeSetChangeStoresSourceMemoryIdWhenGiven() throws {
        let ctx = ModelContext(try container())
        let sessionID = try seedPlan(in: ctx)
        let tool = ProposeSetChangeTool(context: ctx)
        let memID = UUID()

        let args = "{\"plannedSessionID\": \"\(sessionID.uuidString)\", \"exerciseID\": \"bench\", \"targetSets\": 4, \"rationale\": \"add volume\", \"sourceMemoryId\": \"\(memID.uuidString)\"}"
        let result = tool.run(argsJSON: args)

        #expect(!result.contains("error"))
        let pending = try ctx.fetch(FetchDescriptor<PendingCoachSuggestion>())
        #expect(pending[0].sourceMemoryID == memID)
    }

    @Test func proposeSetChangeRejectsHallucinatedSession() throws {
        let ctx = ModelContext(try container())
        _ = try seedPlan(in: ctx)
        let tool = ProposeSetChangeTool(context: ctx)

        let args = "{\"plannedSessionID\": \"\(UUID().uuidString)\", \"exerciseID\": \"bench\", \"targetSets\": 4, \"rationale\": \"test\"}"
        let result = tool.run(argsJSON: args)

        #expect(result.contains("error"))
        #expect(try ctx.fetch(FetchDescriptor<PendingCoachSuggestion>()).isEmpty)
    }

    @Test func proposeSetChangeRejectsExerciseNotInSession() throws {
        let ctx = ModelContext(try container())
        let sessionID = try seedPlan(in: ctx)
        let tool = ProposeSetChangeTool(context: ctx)

        let args = "{\"plannedSessionID\": \"\(sessionID.uuidString)\", \"exerciseID\": \"incline_bench\", \"targetSets\": 4, \"rationale\": \"test\"}"
        let result = tool.run(argsJSON: args)

        #expect(result.contains("error"))
        #expect(try ctx.fetch(FetchDescriptor<PendingCoachSuggestion>()).isEmpty)
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

    @Test func getUpcomingSessionsReflectsAOneDayExerciseEdit() throws {
        let d = UserDefaults.standard
        let keys = [WorkoutScheduleStore.scheduleKey, WorkoutScheduleStore.dayPlanKey,
                    WorkoutScheduleStore.autoPlanKey, WorkoutScheduleStore.dayWorkoutOverrideKey]
        let saved = keys.map { d.string(forKey: $0) }
        for k in keys { d.removeObject(forKey: k) }
        defer { for (k, v) in zip(keys, saved) { d.set(v, forKey: k) } }

        let ctx = ModelContext(try container())
        _ = try seedPlan(in: ctx)
        let plan = try #require(try ctx.fetch(FetchDescriptor<StoredPlan>()).first).decodedPlan()
        let cal = WorkoutScheduleStore.calendar
        let today = cal.startOfDay(for: .now)
        // Recurring routine only on today's weekday, so the plan's one session
        // is scheduled exactly once this week.
        WorkoutScheduleStore.saveWeekSchedule([WorkoutScheduleStore.mondayFirstIndex(for: today): UUID()])
        #expect(WorkoutScheduleStore.replaceExercise("bench", with: catalog().exercise(id: "incline_bench")!,
            on: today, in: plan, catalog: catalog(), origin: .manual))

        let result = GetUpcomingSessionsTool(context: ctx, catalog: catalog()).run(argsJSON: "{}")
        let json = try JSONSerialization.jsonObject(with: Data(result.utf8)) as! [String: Any]
        let sessions = json["sessions"] as! [[String: Any]]
        let scheduled = try #require(sessions.first { $0["scheduledDate"] != nil })

        // The AI sees the one-day edited list, not the recurring "bench".
        #expect(scheduled["exercises"] as? [String] == ["incline_bench"])
    }
}
