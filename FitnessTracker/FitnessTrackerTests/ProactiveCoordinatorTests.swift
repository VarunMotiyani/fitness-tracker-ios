import Testing
import SwiftData
import Foundation
import FitnessDomain
import ExerciseCatalog
@testable import FitnessTracker

@MainActor
@Suite struct ProactiveCoordinatorTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: UserProfile.self, StoredPlan.self, ProviderProfile.self, AICallRecord.self,
            CompletedSessionModel.self, CompletedEntryModel.self, LoggedSetModel.self,
            BodyweightEntryModel.self, DailyCheckinModel.self, ObservationModel.self,
            PersonalRecordModel.self, CoachMemoryModel.self,
            CoachNoteModel.self, WeeklySummaryModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
    private func exercise(_ id: String) -> Exercise {
        Exercise(id: id, name: id.capitalized, primaryMuscle: .chest, secondaryMuscles: [],
                 equipment: .barbell, mechanic: .compound, force: .push,
                 difficulty: .intermediate, isUnilateral: false, instructions: [], imagePaths: [])
    }
    private func catalog() -> CatalogStore { CatalogStore(exercises: [exercise("bench"), exercise("dips")]) }
    private func settings(all: Bool = true) -> ProactiveSettings {
        ProactiveSettings(dailyOn: all, weeklyOn: all, inbodyOn: all, checkinOn: all, patternOn: all,
                          reminderHour: 8, reminderMinute: 0)
    }
    private func seedPlan(in ctx: ModelContext) throws {
        let plan = WeeklyPlan(weekStartDate: Date(), source: .ruleEngine, rationale: "t",
            sessions: [PlannedSession(id: UUID(), order: 0, focusMuscles: [.chest], items: [
                PlannedItem(exerciseID: "bench", targetSets: 3, targetReps: RepRange(min: 6, max: 8),
                            targetLoadKg: 60, restSeconds: 90, coachNote: ""),
                PlannedItem(exerciseID: "dips", targetSets: 3, targetReps: RepRange(min: 8, max: 12),
                            targetLoadKg: nil, restSeconds: 90, coachNote: "")
            ])], weeklyVolumeTargets: [])
        ctx.insert(try StoredPlan(plan: plan, hadValidationIssues: false))
        try ctx.save()
    }

    @Test func dailyNarrationWritesACoachNoteWhenDue() async throws {
        let ctx = ModelContext(try container())
        try seedPlan(in: ctx)
        UserDefaults.standard.removeObject(forKey: "proactive.daily.lastGeneratedDay")
        let final = #"{"decision":"final","final":{"narration":"Push day — lead with dips, chest is fresh."}}"#
        let provider = StubLLMProvider(responses: [.success(final)])
        let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: provider,
                                         activeProfile: nil, settings: settings())

        await coord.runDueChecks()

        let notes = try ctx.fetch(FetchDescriptor<CoachNoteModel>())
        #expect(notes.contains { $0.kindRaw == "daily" })
    }

    @Test func dailyNarrationSkippedWhenAlreadyGeneratedToday() async throws {
        let ctx = ModelContext(try container())
        try seedPlan(in: ctx)
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        UserDefaults.standard.set(df.string(from: Date()), forKey: "proactive.daily.lastGeneratedDay")
        let provider = StubLLMProvider(responses: [])
        let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: provider,
                                         activeProfile: nil, settings: settings())

        await coord.runDueChecks()

        #expect(try ctx.fetch(FetchDescriptor<CoachNoteModel>()).filter { $0.kindRaw == "daily" }.isEmpty)
    }

    @Test func noProviderSkipsLLMItems() async throws {
        let ctx = ModelContext(try container())
        try seedPlan(in: ctx)
        UserDefaults.standard.removeObject(forKey: "proactive.daily.lastGeneratedDay")
        let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: nil,
                                         activeProfile: nil, settings: settings())

        await coord.runDueChecks()

        #expect(try ctx.fetch(FetchDescriptor<CoachNoteModel>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<AICallRecord>()).isEmpty)
    }

    @Test func dailyToggleOffSkipsIt() async throws {
        let ctx = ModelContext(try container())
        try seedPlan(in: ctx)
        UserDefaults.standard.removeObject(forKey: "proactive.daily.lastGeneratedDay")
        let provider = StubLLMProvider(responses: [])
        var s = settings(); s.dailyOn = false
        let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: provider,
                                         activeProfile: nil, settings: s)

        await coord.runDueChecks()

        #expect(try ctx.fetch(FetchDescriptor<CoachNoteModel>()).filter { $0.kindRaw == "daily" }.isEmpty)
    }
}
