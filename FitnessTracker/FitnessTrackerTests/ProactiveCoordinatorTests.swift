import Testing
import SwiftData
import Foundation
import FitnessDomain
import ExerciseCatalog
import Metrics
import RuleEngine
@testable import FitnessTracker

@MainActor
@Suite(.serialized) struct ProactiveCoordinatorTests {
    /// Every `proactive.*` key any test in this suite writes. Called at the
    /// start of each test and via `defer` at the end so a stray key from one
    /// test can't leak into the next (the suite is `.serialized`).
    private func clearProactiveDefaults() {
        let d = UserDefaults.standard
        d.removeObject(forKey: "proactive.daily.lastGeneratedDay")
        d.removeObject(forKey: "proactive.weekly.lastWeekStart")
        d.removeObject(forKey: "proactive.checkin.lastReactedDay")
        d.removeObject(forKey: "proactive.missedWeek.lastWeekStart")
        // The coordinator calls WorkoutScheduleStore.refresh(); keep its keys
        // out of the suite's shared UserDefaults.
        d.removeObject(forKey: "gym_week_schedule_json")
        d.removeObject(forKey: "gym_day_plan_json")
        d.removeObject(forKey: "gym_day_plan_auto_json")
        for key in d.dictionaryRepresentation().keys where key.hasPrefix("proactive.patternNudge.") {
            d.removeObject(forKey: key)
        }
    }

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
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = .appWeek
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
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
        clearProactiveDefaults()
        defer { clearProactiveDefaults() }
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
        clearProactiveDefaults()
        defer { clearProactiveDefaults() }
        let ctx = ModelContext(try container())
        try seedPlan(in: ctx)
        UserDefaults.standard.set(Self.todayString(), forKey: "proactive.daily.lastGeneratedDay")
        // Stub has a valid narration ready — the only reason no note appears is the dedup key.
        let final = #"{"decision":"final","final":{"narration":"Push day — chest is fresh."}}"#
        let provider = StubLLMProvider(responses: [.success(final)])
        var s = settings(); s.weeklyOn = false; s.patternOn = false; s.inbodyOn = false
        let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: provider,
                                         activeProfile: nil, settings: s)

        await coord.runDueChecks()

        #expect(try ctx.fetch(FetchDescriptor<CoachNoteModel>()).filter { $0.kindRaw == "daily" }.isEmpty)
    }

    @Test func noProviderMakesNoBilledAICalls() async throws {
        clearProactiveDefaults()
        defer { clearProactiveDefaults() }
        let ctx = ModelContext(try container())
        try seedPlan(in: ctx)
        UserDefaults.standard.removeObject(forKey: "proactive.daily.lastGeneratedDay")
        let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: nil,
                                         activeProfile: nil, settings: settings())

        await coord.runDueChecks()

        // Offline data-backed fallback cards are allowed; a real LLM call is not.
        #expect(try ctx.fetch(FetchDescriptor<AICallRecord>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<CoachNoteModel>()).allSatisfy {
            ["daily", "weekly"].contains($0.kindRaw)
        })
    }

    @Test func missedWeekScoldWritesANoteAndDedupsWithinTheWeek() async throws {
        clearProactiveDefaults()
        defer { clearProactiveDefaults() }
        let ctx = ModelContext(try container())
        try seedPlan(in: ctx)
        let final = #"{"decision":"final","final":{"taunt":"Two sessions gone and no day left. Chest and back untouched. Monday, no excuses."}}"#
        let provider = StubLLMProvider(responses: [.success(final), .success(final)])
        var s = settings(); s.dailyOn = false; s.patternOn = false; s.inbodyOn = false
        UserDefaults.standard.set(Self.todayString(), forKey: "proactive.daily.lastGeneratedDay")
        let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: provider,
                                         activeProfile: nil, settings: s)

        let unplaced = [Scheduling.MissedSessionReschedule.Unplaced(originalDateKey: "2026-09-07", routineID: "push")]
        await coord.reactToMissedWeek(unplaced)
        await coord.reactToMissedWeek(unplaced) // second call same week — must not add a second card

        let notes = try ctx.fetch(FetchDescriptor<CoachNoteModel>()).filter { $0.kindRaw == "missedWeek" }
        #expect(notes.count == 1)
        #expect(!(notes.first?.text.isEmpty ?? true))
    }

    @Test func missedWeekScoldFallsBackToACannedTauntOffline() async throws {
        clearProactiveDefaults()
        defer { clearProactiveDefaults() }
        let ctx = ModelContext(try container())
        try seedPlan(in: ctx)
        let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: nil,
                                         activeProfile: nil, settings: settings())

        await coord.reactToMissedWeek([
            .init(originalDateKey: "2026-09-07", routineID: "push"),
            .init(originalDateKey: "2026-09-09", routineID: "pull"),
        ])

        let notes = try ctx.fetch(FetchDescriptor<CoachNoteModel>()).filter { $0.kindRaw == "missedWeek" }
        #expect(notes.count == 1)
        #expect(notes.first?.text.contains("2 session") == true)
        #expect(try ctx.fetch(FetchDescriptor<AICallRecord>()).isEmpty)
    }

    @Test func missedWeekScoldSkippedWhenNothingUnrecoverable() async throws {
        clearProactiveDefaults()
        defer { clearProactiveDefaults() }
        let ctx = ModelContext(try container())
        let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: nil,
                                         activeProfile: nil, settings: settings())

        await coord.reactToMissedWeek([])

        #expect(try ctx.fetch(FetchDescriptor<CoachNoteModel>()).filter { $0.kindRaw == "missedWeek" }.isEmpty)
    }

    @Test func weeklySummaryWritesModelAndNoteWhenDue() async throws {
        clearProactiveDefaults()
        defer { clearProactiveDefaults() }
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

    @Test func weeklySummarySkippedWhenAlreadyDoneForThisRecapWeek() async throws {
        clearProactiveDefaults()
        defer { clearProactiveDefaults() }
        let ctx = ModelContext(try container())
        try seedPlan(in: ctx)
        let provider = StubLLMProvider(responses: [])
        var s = settings(); s.dailyOn = false; s.patternOn = false
        let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: provider,
                                         activeProfile: nil, settings: s)
        // Flag already carries the key for the week the recap currently targets.
        if let key = coord.currentRecapWeekKey() {
            UserDefaults.standard.set(key, forKey: "proactive.weekly.lastWeekStart")
        }

        await coord.runDueChecks()

        // Nothing written and no billed call — actually skipped, not run-then-fallback.
        #expect(try ctx.fetch(FetchDescriptor<WeeklySummaryModel>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<CoachNoteModel>()).filter { $0.kindRaw == "weekly" }.isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<AICallRecord>()).isEmpty)
    }

    @Test func weeklyDueUntilItRunsThenNotAgainForTheSameWeek() async throws {
        clearProactiveDefaults()
        defer { clearProactiveDefaults() }
        let ctx = ModelContext(try container())
        let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: nil,
                                         activeProfile: nil, settings: settings())

        #expect(coord.isWeeklyDue())
        if let key = coord.currentRecapWeekKey() {
            UserDefaults.standard.set(key, forKey: "proactive.weekly.lastWeekStart")
        }
        #expect(!coord.isWeeklyDue())
    }

    @Test func dailyToggleOffSkipsIt() async throws {
        clearProactiveDefaults()
        defer { clearProactiveDefaults() }
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
        clearProactiveDefaults()
        defer { clearProactiveDefaults() }
        let ctx = ModelContext(try container())
        UserDefaults.standard.set(Self.todayString(), forKey: "proactive.daily.lastGeneratedDay")
        let weekIso = ISO8601DateFormatter().string(from: Calendar.appWeek.dateInterval(of: .weekOfYear, for: .now)!.start)
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
        clearProactiveDefaults()
        defer { clearProactiveDefaults() }
        let ctx = ModelContext(try container())
        UserDefaults.standard.set(Self.todayString(), forKey: "proactive.daily.lastGeneratedDay")
        UserDefaults.standard.set(ISO8601DateFormatter().string(from: Calendar.appWeek.dateInterval(of: .weekOfYear, for: .now)!.start),
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

    @Test func runDueChecksSweepsOrphanPatternNudgeKeys() async throws {
        clearProactiveDefaults()
        defer { clearProactiveDefaults() }
        let ctx = ModelContext(try container())
        let mem = CoachMemoryModel(kindRaw: "responsePattern", statement: "Skips pull day when busy",
                                   confidence: 0.8, sourceKind: "agent", createdAt: .now, lastConfirmedAt: .now)
        ctx.insert(mem)
        try ctx.save()

        let liveKey = "proactive.patternNudge.\(mem.id.uuidString)"
        let orphanKey = "proactive.patternNudge.\(UUID().uuidString)"
        let stamp = ISO8601DateFormatter().string(from: .now)
        UserDefaults.standard.set(stamp, forKey: liveKey)
        UserDefaults.standard.set(stamp, forKey: orphanKey)

        // provider nil: runDueChecks returns after the sweep, before any LLM item.
        var s = settings(); s.dailyOn = false; s.weeklyOn = false; s.inbodyOn = false
        let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: nil,
                                         activeProfile: nil, settings: s)

        await coord.runDueChecks()

        #expect(UserDefaults.standard.string(forKey: liveKey) != nil)
        #expect(UserDefaults.standard.string(forKey: orphanKey) == nil)
    }

    @Test func checkinReactionFiresAboveSorenessThreshold() async throws {
        clearProactiveDefaults()
        defer { clearProactiveDefaults() }
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
        clearProactiveDefaults()
        defer { clearProactiveDefaults() }
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
        clearProactiveDefaults()
        defer { clearProactiveDefaults() }
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

    // MARK: - I7: positive billing

    @Test func dailyNarrationInsertsOneBilledAICallRecord() async throws {
        clearProactiveDefaults()
        defer { clearProactiveDefaults() }
        let ctx = ModelContext(try container())
        try seedPlan(in: ctx)
        ctx.insert(UserProfile(
            goalRaw: "buildMuscle", experienceRaw: "intermediate", heightCm: 178, weightKg: 75,
            birthYear: 2000, sexRaw: "male", sessionsPerWeek: 4, sessionLengthMinutes: 60,
            availableEquipmentRaws: ["barbell"], excludedMuscleRaws: [], excludedExerciseIDs: []))
        try ctx.save()

        let profile = ProviderProfile(
            displayName: "TestCo", adapterKind: .openAICompatible, baseURL: "https://x",
            modelID: "test-model", apiKeyRef: nil, supportsVision: false,
            pricePerMTokIn: 3.0, pricePerMTokOut: 15.0, pricePerMTokCached: 0.3)

        let final = #"{"decision":"final","final":{"narration":"Push day — lead with dips, chest is fresh."}}"#
        let provider = StubLLMProvider(responses: [.success(final)])
        var s = settings(); s.weeklyOn = false; s.patternOn = false; s.inbodyOn = false
        let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: provider,
                                         activeProfile: profile, settings: s)

        await coord.runDueChecks()

        let records = try ctx.fetch(FetchDescriptor<AICallRecord>())
        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(record.callType == "dailyNarration")
        #expect(record.success == true)
        #expect(record.costUSD > 0)
    }

    // MARK: - C1 regression: daily narration survives a completed training cycle

    @Test func todaysOrNextSessionFallsBackWhenEverySessionCompletedInAPriorWeek() async throws {
        clearProactiveDefaults()
        defer { clearProactiveDefaults() }
        let ctx = ModelContext(try container())
        let s1 = UUID(), s2 = UUID()
        let plan = WeeklyPlan(weekStartDate: Date(), source: .ruleEngine, rationale: "t", sessions: [
            PlannedSession(id: s1, order: 0, focusMuscles: [.chest], items: [
                PlannedItem(exerciseID: "bench", targetSets: 3, targetReps: RepRange(min: 6, max: 8),
                            targetLoadKg: 60, restSeconds: 90, coachNote: "")]),
            PlannedSession(id: s2, order: 1, focusMuscles: [.back], items: [
                PlannedItem(exerciseID: "dips", targetSets: 3, targetReps: RepRange(min: 8, max: 12),
                            targetLoadKg: nil, restSeconds: 90, coachNote: "")])
        ], weeklyVolumeTargets: [])
        ctx.insert(try StoredPlan(plan: plan, hadValidationIssues: false))
        let tenDaysAgo = Calendar.appWeek.date(byAdding: .day, value: -10, to: .now)!
        for sid in [s1, s2] {
            let done = CompletedSessionModel(startedAt: tenDaysAgo, weekdayRaw: 0, timeOfDayMinutes: 480,
                                             plannedDurationMin: 60, energyRaw: "ok", timeAvailableMin: 60,
                                             plannedSessionID: sid)
            done.finishedAt = tenDaysAgo.addingTimeInterval(3600)
            ctx.insert(done)
        }
        try ctx.save()

        let final = #"{"decision":"final","final":{"narration":"Back to it — start with bench."}}"#
        let provider = StubLLMProvider(responses: [.success(final)])
        var st = settings(); st.weeklyOn = false; st.patternOn = false; st.inbodyOn = false
        let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: provider,
                                         activeProfile: nil, settings: st)

        await coord.runDueChecks()

        #expect(try ctx.fetch(FetchDescriptor<CoachNoteModel>()).contains { $0.kindRaw == "daily" })
    }

    @Test func todaysOrNextSessionSkipsASessionCompletedThisWeek() async throws {
        clearProactiveDefaults()
        defer { clearProactiveDefaults() }
        let ctx = ModelContext(try container())
        let s1 = UUID(), s2 = UUID()
        let plan = WeeklyPlan(weekStartDate: Date(), source: .ruleEngine, rationale: "t", sessions: [
            PlannedSession(id: s1, order: 0, focusMuscles: [.chest], items: [
                PlannedItem(exerciseID: "bench", targetSets: 3, targetReps: RepRange(min: 6, max: 8),
                            targetLoadKg: 60, restSeconds: 90, coachNote: "")]),
            PlannedSession(id: s2, order: 1, focusMuscles: [.back], items: [
                PlannedItem(exerciseID: "dips", targetSets: 3, targetReps: RepRange(min: 8, max: 12),
                            targetLoadKg: nil, restSeconds: 90, coachNote: "")])
        ], weeklyVolumeTargets: [])
        ctx.insert(try StoredPlan(plan: plan, hadValidationIssues: false))
        let done = CompletedSessionModel(startedAt: .now, weekdayRaw: 0, timeOfDayMinutes: 480,
                                         plannedDurationMin: 60, energyRaw: "ok", timeAvailableMin: 60,
                                         plannedSessionID: s1)
        done.finishedAt = .now
        ctx.insert(done)
        try ctx.save()

        let final = #"{"decision":"final","final":{"narration":"Back day — go."}}"#
        let provider = StubLLMProvider(responses: [.success(final)])
        var st = settings(); st.weeklyOn = false; st.patternOn = false; st.inbodyOn = false
        let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: provider,
                                         activeProfile: nil, settings: st)

        await coord.runDueChecks()

        // The narration prompt names the chosen session's focus muscles; the
        // one completed this week (chest, order 0) must be skipped for back.
        #expect(provider.lastUser.contains("Back"))
        #expect(!provider.lastUser.contains("Chest Day"))
    }
}
