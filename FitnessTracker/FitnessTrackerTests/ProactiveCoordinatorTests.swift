import Testing
import SwiftData
import Foundation
import FitnessDomain
import ExerciseCatalog
import Metrics
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
    static func todayString() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.calendar = .isoUTC
        return f.string(from: .now)
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

    @Test func weeklySummaryWritesModelAndNoteWhenDue() async throws {
        let ctx = ModelContext(try container())
        try seedPlan(in: ctx)
        UserDefaults.standard.removeObject(forKey: "proactive.weekly.lastWeekStart")
        UserDefaults.standard.set(Self.todayString(), forKey: "proactive.daily.lastGeneratedDay") // isolate: daily not due
        let final = #"{"decision":"final","final":{"headline":"Solid week","body":"3 of 4 sessions, chest twice.","nextWeekFocus":"Hit back harder."}}"#
        let provider = StubLLMProvider(responses: [.success(final)])
        var s = settings(); s.dailyOn = false; s.patternOn = false
        let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: provider,
                                         activeProfile: nil, settings: s)

        await coord.runDueChecks()

        #expect(try ctx.fetch(FetchDescriptor<WeeklySummaryModel>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<CoachNoteModel>()).contains { $0.kindRaw == "weekly" })
    }

    @Test func weeklySummarySkippedWhenAlreadyDoneThisWeek() async throws {
        let ctx = ModelContext(try container())
        try seedPlan(in: ctx)
        let weekStart = Calendar.isoUTC.dateInterval(of: .weekOfYear, for: .now)!.start
        let iso = ISO8601DateFormatter().string(from: weekStart)
        UserDefaults.standard.set(iso, forKey: "proactive.weekly.lastWeekStart")
        let provider = StubLLMProvider(responses: [])
        var s = settings(); s.dailyOn = false; s.patternOn = false
        let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: provider,
                                         activeProfile: nil, settings: s)

        await coord.runDueChecks()

        #expect(try ctx.fetch(FetchDescriptor<WeeklySummaryModel>()).isEmpty)
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

    @Test func patternNudgeWritesANoteForAHighConfidenceResponsePattern() async throws {
        let ctx = ModelContext(try container())
        UserDefaults.standard.set(Self.todayString(), forKey: "proactive.daily.lastGeneratedDay")
        let weekIso = ISO8601DateFormatter().string(from: Calendar.isoUTC.dateInterval(of: .weekOfYear, for: .now)!.start)
        UserDefaults.standard.set(weekIso, forKey: "proactive.weekly.lastWeekStart")
        let mem = CoachMemoryModel(kindRaw: "responsePattern", statement: "Skips pull day when the week is busy",
                                   confidence: 0.8, sourceKind: "agent", createdAt: .now, lastConfirmedAt: .now)
        ctx.insert(mem)
        try ctx.save()
        UserDefaults.standard.removeObject(forKey: "proactive.patternNudge.\(mem.id.uuidString)")
        let final = #"{"decision":"final","final":{"nudge":"You've skipped pull day 3 weeks running — do it first this week."}}"#
        let provider = StubLLMProvider(responses: [.success(final)])
        var s = settings(); s.dailyOn = false; s.weeklyOn = false
        let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: provider,
                                         activeProfile: nil, settings: s)

        await coord.runDueChecks()

        #expect(try ctx.fetch(FetchDescriptor<CoachNoteModel>()).contains { $0.kindRaw == "pattern" })
    }

    @Test func patternNudgeSkipsLowConfidenceAndRecentlyNudged() async throws {
        let ctx = ModelContext(try container())
        UserDefaults.standard.set(Self.todayString(), forKey: "proactive.daily.lastGeneratedDay")
        UserDefaults.standard.set(ISO8601DateFormatter().string(from: Calendar.isoUTC.dateInterval(of: .weekOfYear, for: .now)!.start),
                                  forKey: "proactive.weekly.lastWeekStart")
        let lowConf = CoachMemoryModel(kindRaw: "responsePattern", statement: "Weak", confidence: 0.4,
                                       sourceKind: "agent", createdAt: .now, lastConfirmedAt: .now)
        let nudged = CoachMemoryModel(kindRaw: "responsePattern", statement: "Recently nudged", confidence: 0.9,
                                      sourceKind: "agent", createdAt: .now, lastConfirmedAt: .now)
        ctx.insert(lowConf); ctx.insert(nudged); try ctx.save()
        UserDefaults.standard.set(ISO8601DateFormatter().string(from: .now),
                                  forKey: "proactive.patternNudge.\(nudged.id.uuidString)")
        let provider = StubLLMProvider(responses: [])
        var s = settings(); s.dailyOn = false; s.weeklyOn = false
        let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: provider,
                                         activeProfile: nil, settings: s)

        await coord.runDueChecks()

        #expect(try ctx.fetch(FetchDescriptor<CoachNoteModel>()).filter { $0.kindRaw == "pattern" }.isEmpty)
    }

    @Test func checkinReactionFiresAboveSorenessThreshold() async throws {
        let ctx = ModelContext(try container())
        let checkin = DailyCheckinModel(date: Date())
        checkin.soreness = 8
        checkin.note = "quads destroyed"
        ctx.insert(checkin); try ctx.save()
        let final = #"{"decision":"final","final":{"message":"Skip legs today, walk instead."}}"#
        let provider = StubLLMProvider(responses: [.success(final)])
        let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: provider,
                                         activeProfile: nil, settings: settings())

        await coord.reactToCheckin(checkin)

        #expect(try ctx.fetch(FetchDescriptor<CoachNoteModel>()).contains { $0.kindRaw == "checkin" })
    }

    @Test func checkinReactionSkippedBelowThreshold() async throws {
        let ctx = ModelContext(try container())
        let checkin = DailyCheckinModel(date: Date())
        checkin.soreness = 3
        checkin.sleepQuality = 8
        ctx.insert(checkin); try ctx.save()
        let provider = StubLLMProvider(responses: [])
        let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: provider,
                                         activeProfile: nil, settings: settings())

        await coord.reactToCheckin(checkin)

        #expect(try ctx.fetch(FetchDescriptor<CoachNoteModel>()).filter { $0.kindRaw == "checkin" }.isEmpty)
    }

    @Test func checkinReactionSkippedWhenToggledOff() async throws {
        let ctx = ModelContext(try container())
        let checkin = DailyCheckinModel(date: Date())
        checkin.soreness = 9
        ctx.insert(checkin); try ctx.save()
        let provider = StubLLMProvider(responses: [])
        var s = settings(); s.checkinOn = false
        let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: provider,
                                         activeProfile: nil, settings: s)

        await coord.reactToCheckin(checkin)

        #expect(try ctx.fetch(FetchDescriptor<CoachNoteModel>()).filter { $0.kindRaw == "checkin" }.isEmpty)
    }
}
