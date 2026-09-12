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
        try ModelContainer(
            for: StoredPlan.self, PendingCoachSuggestion.self, BodyweightEntryModel.self, UserProfile.self,
            ChatMessageModel.self, ChatSummaryModel.self, AICallRecord.self, CompletedSessionModel.self,
            CompletedEntryModel.self, LoggedSetModel.self, DailyCheckinModel.self, ObservationModel.self,
            PersonalRecordModel.self, CoachMemoryModel.self, CoachNoteModel.self, WeeklySummaryModel.self,
            CustomExerciseModel.self, ProviderProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func seedProfile(in ctx: ModelContext) -> UserProfile {
        let profile = UserProfile(
            goalRaw: "buildMuscle", experienceRaw: "intermediate", heightCm: 178, weightKg: 75,
            birthYear: 2000, sexRaw: "male", sessionsPerWeek: 3, sessionLengthMinutes: 60,
            availableEquipmentRaws: ["barbell"], excludedMuscleRaws: [], excludedExerciseIDs: [])
        ctx.insert(profile)
        return profile
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

    private func decodeCardPayload<T: Decodable>(_ json: String, as type: T.Type) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - start_workout

    @Test func startWorkoutRecordsAStartWorkoutCard() throws {
        let ctx = ModelContext(try container())
        let sessionID = try seedPlan(in: ctx)
        let sink = CoachActionSink()
        let tool = StartWorkoutTool(context: ctx, sink: sink)

        let result = tool.run(argsJSON: "{\"plannedSessionID\": \"\(sessionID.uuidString)\"}")

        #expect(!result.contains("error"))
        #expect(sink.cardRequests.count == 1)
        #expect(sink.cardRequests.first?.kind == .startWorkout)
        let payload = try #require(decodeCardPayload(sink.cardRequests[0].payloadJSON, as: StartWorkoutCardPayload.self))
        #expect(payload.plannedSessionID == sessionID)
    }

    @Test func startWorkoutRejectsUnknownSession() throws {
        let ctx = ModelContext(try container())
        _ = try seedPlan(in: ctx)
        let sink = CoachActionSink()
        let tool = StartWorkoutTool(context: ctx, sink: sink)

        let result = tool.run(argsJSON: "{\"plannedSessionID\": \"\(UUID().uuidString)\"}")

        #expect(result.contains("error"))
        #expect(sink.cardRequests.isEmpty)
    }

    // MARK: - regenerate_plan

    @Test func regeneratePlanOnlyFlagsTheSink() {
        let sink = CoachActionSink()
        let tool = RegeneratePlanTool(sink: sink)

        let result = tool.run(argsJSON: "{\"reason\": \"switch to 5 days\"}")

        #expect(!result.contains("error"))
        #expect(sink.requestedPlanRegeneration)
        // The card itself is the coordinator's job (it needs to await the
        // actual generation) — this tool only ever flags the request.
        #expect(sink.cardRequests.isEmpty)
    }

    // MARK: - set_day_to_rest

    @Test func setDayToRestWritesTheOverrideAndRecordsACard() throws {
        let d = UserDefaults.standard
        let key = WorkoutScheduleStore.dayPlanKey
        let saved = d.string(forKey: key)
        defer { d.set(saved, forKey: key) }
        d.removeObject(forKey: key)

        let sink = CoachActionSink()
        let tool = SetDayToRestTool(sink: sink)
        let result = tool.run(argsJSON: "{\"date\": \"2026-09-15\"}")

        #expect(!result.contains("error"))
        #expect(WorkoutScheduleStore.userDayPlan["2026-09-15"] == "rest")
        #expect(sink.cardRequests.count == 1)
        #expect(sink.cardRequests.first?.kind == .appliedChange)
        let payload = try #require(decodeCardPayload(sink.cardRequests[0].payloadJSON, as: AppliedChangeCardPayload.self))
        #expect(payload.detail == "2026-09-15")
    }

    @Test func setDayToRestRejectsBadDateFormat() {
        let sink = CoachActionSink()
        let tool = SetDayToRestTool(sink: sink)
        let result = tool.run(argsJSON: "{\"date\": \"not-a-date\"}")
        #expect(result.contains("error"))
        #expect(sink.cardRequests.isEmpty)
    }

    // MARK: - apply_exercise_swap / apply_set_change (direct, no approval card)

    @Test func applyExerciseSwapMutatesThePlanDirectlyAndRecordsACard() throws {
        let ctx = ModelContext(try container())
        let sessionID = try seedPlan(in: ctx)
        let sink = CoachActionSink()
        let tool = ApplyExerciseSwapTool(context: ctx, catalog: catalog(), sink: sink)

        let args = "{\"plannedSessionID\": \"\(sessionID.uuidString)\", \"exerciseID\": \"bench\", \"replacementExerciseID\": \"incline_bench\", \"rationale\": \"asked directly\"}"
        let result = tool.run(argsJSON: args)

        #expect(!result.contains("error"))
        // Unlike propose_exercise_swap, nothing is left pending — it's applied.
        #expect(try ctx.fetch(FetchDescriptor<PendingCoachSuggestion>()).isEmpty)
        let plan = try #require(try ctx.fetch(FetchDescriptor<StoredPlan>()).first).decodedPlan()
        #expect(plan.sessions.first?.items.first?.exerciseID == "incline_bench")
        #expect(sink.cardRequests.count == 1)
        #expect(sink.cardRequests.first?.kind == .appliedChange)
        let payload = try #require(decodeCardPayload(sink.cardRequests[0].payloadJSON, as: AppliedChangeCardPayload.self))
        #expect(payload.detail.contains("bench") && payload.detail.contains("incline_bench"))
    }

    @Test func applyExerciseSwapRejectsUnknownReplacement() throws {
        let ctx = ModelContext(try container())
        let sessionID = try seedPlan(in: ctx)
        let sink = CoachActionSink()
        let tool = ApplyExerciseSwapTool(context: ctx, catalog: catalog(), sink: sink)

        let args = "{\"plannedSessionID\": \"\(sessionID.uuidString)\", \"exerciseID\": \"bench\", \"replacementExerciseID\": \"nonexistent\", \"rationale\": \"x\"}"
        let result = tool.run(argsJSON: args)

        #expect(result.contains("error"))
        let plan = try #require(try ctx.fetch(FetchDescriptor<StoredPlan>()).first).decodedPlan()
        #expect(plan.sessions.first?.items.first?.exerciseID == "bench")
        #expect(sink.cardRequests.isEmpty)
    }

    @Test func applySetChangeMutatesThePlanDirectlyAndRecordsACard() throws {
        let ctx = ModelContext(try container())
        let sessionID = try seedPlan(in: ctx)
        let sink = CoachActionSink()
        let tool = ApplySetChangeTool(context: ctx, catalog: catalog(), sink: sink)

        let args = "{\"plannedSessionID\": \"\(sessionID.uuidString)\", \"exerciseID\": \"bench\", \"targetSets\": 5, \"rationale\": \"asked directly\"}"
        let result = tool.run(argsJSON: args)

        #expect(!result.contains("error"))
        #expect(try ctx.fetch(FetchDescriptor<PendingCoachSuggestion>()).isEmpty)
        let plan = try #require(try ctx.fetch(FetchDescriptor<StoredPlan>()).first).decodedPlan()
        #expect(plan.sessions.first?.items.first?.targetSets == 5)
        #expect(sink.cardRequests.count == 1)
        let payload = try #require(decodeCardPayload(sink.cardRequests[0].payloadJSON, as: AppliedChangeCardPayload.self))
        #expect(payload.detail.contains("5 sets"))
    }

    @Test func applySetChangeRejectsImplausibleSets() throws {
        let ctx = ModelContext(try container())
        let sessionID = try seedPlan(in: ctx)
        let sink = CoachActionSink()
        let tool = ApplySetChangeTool(context: ctx, catalog: catalog(), sink: sink)

        let args = "{\"plannedSessionID\": \"\(sessionID.uuidString)\", \"exerciseID\": \"bench\", \"targetSets\": 99, \"rationale\": \"x\"}"
        let result = tool.run(argsJSON: args)

        #expect(result.contains("error"))
        #expect(sink.cardRequests.isEmpty)
    }

    // MARK: - log_bodyweight

    @Test func logBodyweightWritesAnEntryAndRecordsACard() throws {
        let ctx = ModelContext(try container())
        let sink = CoachActionSink()
        let tool = LogBodyweightTool(context: ctx, sink: sink)

        let result = tool.run(argsJSON: "{\"kg\": 76.5}")

        #expect(!result.contains("error"))
        let entries = try ctx.fetch(FetchDescriptor<BodyweightEntryModel>())
        #expect(entries.count == 1)
        #expect(entries.first?.kg == 76.5)
        #expect(sink.cardRequests.count == 1)
        let payload = try #require(decodeCardPayload(sink.cardRequests[0].payloadJSON, as: AppliedChangeCardPayload.self))
        #expect(payload.detail == "76.5 kg")
    }

    @Test func logBodyweightRejectsImplausibleWeight() throws {
        let ctx = ModelContext(try container())
        let sink = CoachActionSink()
        let tool = LogBodyweightTool(context: ctx, sink: sink)

        let result = tool.run(argsJSON: "{\"kg\": 5}")

        #expect(result.contains("error"))
        #expect(try ctx.fetch(FetchDescriptor<BodyweightEntryModel>()).isEmpty)
        #expect(sink.cardRequests.isEmpty)
    }

    // MARK: - update_profile

    @Test func updateProfileAppliesSessionsPerWeekAndRecordsACard() throws {
        let ctx = ModelContext(try container())
        let profile = seedProfile(in: ctx)
        let sink = CoachActionSink()
        let tool = UpdateProfileTool(context: ctx, sink: sink)

        let result = tool.run(argsJSON: "{\"sessionsPerWeek\": 5}")

        #expect(!result.contains("error"))
        #expect(profile.sessionsPerWeek == 5)
        #expect(sink.cardRequests.count == 1)
        let payload = try #require(decodeCardPayload(sink.cardRequests[0].payloadJSON, as: AppliedChangeCardPayload.self))
        #expect(payload.detail.contains("sessions/week → 5"))
    }

    @Test func updateProfileAppliesGoalEquipmentAndMuscleExclusion() throws {
        let ctx = ModelContext(try container())
        let profile = seedProfile(in: ctx)
        let sink = CoachActionSink()
        let tool = UpdateProfileTool(context: ctx, sink: sink)

        let result = tool.run(argsJSON: """
        {"goal": "loseFat", "addEquipment": ["dumbbell"], "excludeMuscles": ["lowerBack"]}
        """)

        #expect(!result.contains("error"))
        #expect(profile.goalRaw == "loseFat")
        #expect(profile.availableEquipmentRaws.contains("dumbbell"))
        #expect(profile.excludedMuscleRaws.contains("lowerBack"))
    }

    @Test func updateProfileRejectsUnknownGoal() throws {
        let ctx = ModelContext(try container())
        let profile = seedProfile(in: ctx)
        let sink = CoachActionSink()
        let tool = UpdateProfileTool(context: ctx, sink: sink)

        let result = tool.run(argsJSON: "{\"goal\": \"getShredded\"}")

        #expect(result.contains("error"))
        #expect(profile.goalRaw == "buildMuscle") // unchanged
        #expect(sink.cardRequests.isEmpty)
    }

    @Test func updateProfileRejectsEmptyArgs() throws {
        let ctx = ModelContext(try container())
        _ = seedProfile(in: ctx)
        let sink = CoachActionSink()
        let tool = UpdateProfileTool(context: ctx, sink: sink)

        let result = tool.run(argsJSON: "{}")

        #expect(result.contains("error"))
        #expect(sink.cardRequests.isEmpty)
    }

    @Test func updateProfileRejectsWhenNoProfileExists() throws {
        let ctx = ModelContext(try container())
        let sink = CoachActionSink()
        let tool = UpdateProfileTool(context: ctx, sink: sink)

        let result = tool.run(argsJSON: "{\"sessionsPerWeek\": 4}")

        #expect(result.contains("error"))
    }

    // MARK: - clear_data

    @Test func clearDataRefusesWithoutExplicitConfirmation() throws {
        let ctx = ModelContext(try container())
        let profile = seedProfile(in: ctx)
        ctx.insert(ChatMessageModel(role: "user", text: "clear my data"))
        let sink = CoachActionSink()
        let tool = ClearDataTool(context: ctx, sink: sink)

        let result = tool.run(argsJSON: "{\"confirmed\": false}")

        #expect(result.contains("error"))
        #expect(try ctx.fetch(FetchDescriptor<ChatMessageModel>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<UserProfile>()).first?.id == profile.id)
        #expect(sink.cardRequests.isEmpty)
    }

    @Test func clearDataWipesHistoryButKeepsProfileAndProviderSettings() throws {
        let ctx = ModelContext(try container())
        let profile = seedProfile(in: ctx)
        let providerProfile = ProviderProfile(
            displayName: "Gemini", adapterKind: .gemini, baseURL: nil, modelID: "gemini-3.8-flash",
            apiKeyRef: nil, supportsVision: true, pricePerMTokIn: 0, pricePerMTokOut: 0, pricePerMTokCached: 0)
        ctx.insert(providerProfile)
        ctx.insert(ChatMessageModel(role: "assistant", text: "hey"))
        ctx.insert(CoachMemoryModel(kindRaw: "preference", statement: "likes dumbbells", confidence: 0.5,
                                    sourceKind: "agent", createdAt: .now, lastConfirmedAt: .now))
        try ctx.save() // batch delete only sees persisted rows, not pending inserts
        let sink = CoachActionSink()
        let tool = ClearDataTool(context: ctx, sink: sink)

        let result = tool.run(argsJSON: "{\"confirmed\": true}")

        #expect(!result.contains("error"))
        #expect(try ctx.fetch(FetchDescriptor<ChatMessageModel>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<CoachMemoryModel>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<UserProfile>()).first?.id == profile.id)
        #expect(try ctx.fetch(FetchDescriptor<ProviderProfile>()).first?.id == providerProfile.id)
        #expect(sink.cardRequests.count == 1)
        #expect(sink.cardRequests.first?.kind == .appliedChange)
    }
}
