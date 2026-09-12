import Testing
import SwiftData
import Foundation
import FitnessDomain
import ExerciseCatalog
import LLMKit
@testable import FitnessTracker

@MainActor
@Suite struct AskCoachCoordinatorTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: ChatMessageModel.self, ChatSummaryModel.self, AICallRecord.self,
            CompletedSessionModel.self, CompletedEntryModel.self, LoggedSetModel.self,
            BodyweightEntryModel.self, DailyCheckinModel.self, ObservationModel.self,
            PersonalRecordModel.self, CoachMemoryModel.self,
            StoredPlan.self, PendingCoachSuggestion.self, UserProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    /// Mirrors `SuggestionToolsTests.seedPlan`: a single-session plan with one
    /// planned exercise, so a `propose_exercise_swap` tool call has a real
    /// `plannedSessionID`/`exerciseID` to target.
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

    private func exercise(_ id: String) -> Exercise {
        Exercise(id: id, name: id, primaryMuscle: .chest, secondaryMuscles: [],
                 equipment: .barbell, mechanic: .compound, force: .push,
                 difficulty: .intermediate, isUnilateral: false, instructions: [], imagePaths: [])
    }

    private func catalog() -> CatalogStore { CatalogStore(exercises: [exercise("bench"), exercise("incline_bench")]) }

    @Test func sendPersistsBothMessagesAndReturnsReply() async throws {
        let ctx = ModelContext(try container())
        let finalTurn = """
        {"decision":"final","final":{"reply":"Your chest recovery looks solid today."}}
        """
        let provider = StubLLMProvider(responses: [.success(finalTurn)])
        let coordinator = AskCoachCoordinator(catalog: catalog(), context: ctx, provider: provider, activeProfile: nil)

        let reply = await coordinator.send("How's my chest recovery?")

        #expect(reply.text == "Your chest recovery looks solid today.")
        #expect(reply.isError == false)
        let messages = try ctx.fetch(FetchDescriptor<ChatMessageModel>(sortBy: [SortDescriptor(\.timestamp)]))
        #expect(messages.count == 2)
        #expect(messages[0].role == "user")
        #expect(messages[0].text == "How's my chest recovery?")
        #expect(messages[1].role == "assistant")
        #expect(messages[1].text == "Your chest recovery looks solid today.")
    }

    @Test func sendExecutesProposeExerciseSwapToolAndPersistsSuggestion() async throws {
        let ctx = ModelContext(try container())
        let sessionID = try seedPlan(in: ctx)
        let toolTurn = """
        {"decision":"tool_call","toolCall":{"name":"propose_exercise_swap","argsJSON":"{\\"plannedSessionID\\": \\"\(sessionID.uuidString)\\", \\"exerciseID\\": \\"bench\\", \\"replacementExerciseID\\": \\"incline_bench\\", \\"rationale\\": \\"shoulder discomfort\\"}"}}
        """
        let finalTurn = """
        {"decision":"final","final":{"reply":"I've proposed swapping bench for incline bench."}}
        """
        let provider = StubLLMProvider(responses: [.success(toolTurn), .success(finalTurn)])
        let coordinator = AskCoachCoordinator(catalog: catalog(), context: ctx, provider: provider, activeProfile: nil)

        let reply = await coordinator.send("My shoulder's bothering me on bench, can we swap it?")

        #expect(reply.isError == false)
        #expect(reply.text == "I've proposed swapping bench for incline bench.")
        let pending = try ctx.fetch(FetchDescriptor<PendingCoachSuggestion>())
        #expect(pending.count == 1)
        #expect(pending[0].kind == "exerciseSwap")
        #expect(pending[0].replacementExerciseID == "incline_bench")
        // Also lands inline in the transcript as a real card, not just the
        // reply's prose claiming a proposal was made.
        let messages = try ctx.fetch(FetchDescriptor<ChatMessageModel>(sortBy: [SortDescriptor(\.timestamp)]))
        let cardMessage = try #require(messages.first { $0.cardKind == .suggestion })
        let payload = try #require(cardMessage.decodedCardPayload(as: SuggestionCardPayload.self))
        #expect(payload.suggestionID == pending[0].id)
    }

    @Test func sendExecutesProposeRoutineRevisionToolAndPersistsMemory() async throws {
        let ctx = ModelContext(try container())
        let toolTurn = """
        {"decision":"tool_call","toolCall":{"name":"propose_routine_revision","argsJSON":"{\\"statement\\": \\"Wants more shoulder volume on push days\\", \\"action\\": \\"Add a lateral raise variation\\"}"}}
        """
        let finalTurn = """
        {"decision":"final","final":{"reply":"Got it — I'll factor that into your next plan."}}
        """
        let provider = StubLLMProvider(responses: [.success(toolTurn), .success(finalTurn)])
        let coordinator = AskCoachCoordinator(catalog: catalog(), context: ctx, provider: provider, activeProfile: nil)

        let reply = await coordinator.send("I'd like more shoulder volume on my push days going forward.")

        #expect(reply.isError == false)
        #expect(reply.text == "Got it — I'll factor that into your next plan.")
        let memories = try ctx.fetch(FetchDescriptor<CoachMemoryModel>())
        #expect(memories.count == 1)
        #expect(memories[0].kindRaw == "preference")
        #expect(memories[0].statement == "Wants more shoulder volume on push days")
    }

    @Test func sendRecordsOneAICallRecordPerMessage() async throws {
        let ctx = ModelContext(try container())
        let finalTurn = """
        {"decision":"final","final":{"reply":"Sounds good."}}
        """
        let provider = StubLLMProvider(responses: [.success(finalTurn)])
        let coordinator = AskCoachCoordinator(catalog: catalog(), context: ctx, provider: provider, activeProfile: nil)

        _ = await coordinator.send("test")

        let calls = try ctx.fetch(FetchDescriptor<AICallRecord>())
        #expect(calls.count == 1)
        #expect(calls[0].callType == "askCoach")
    }

    @Test func noProviderReturnsSetupMessageAndPersistsNothing() async throws {
        let ctx = ModelContext(try container())
        let coordinator = AskCoachCoordinator(catalog: catalog(), context: ctx, provider: nil, activeProfile: nil)

        let reply = await coordinator.send("test")

        #expect(!reply.text.isEmpty)
        #expect(reply.isError == true)
        #expect(try ctx.fetch(FetchDescriptor<ChatMessageModel>()).isEmpty)
    }

    @Test func sendExecutesStartWorkoutToolAndPersistsAStartWorkoutCard() async throws {
        let ctx = ModelContext(try container())
        let sessionID = try seedPlan(in: ctx)
        let toolTurn = """
        {"decision":"tool_call","toolCall":{"name":"start_workout","argsJSON":"{\\"plannedSessionID\\": \\"\(sessionID.uuidString)\\"}"}}
        """
        let finalTurn = """
        {"decision":"final","final":{"reply":"Here's your session — tap Start when ready."}}
        """
        let provider = StubLLMProvider(responses: [.success(toolTurn), .success(finalTurn)])
        let coordinator = AskCoachCoordinator(catalog: catalog(), context: ctx, provider: provider, activeProfile: nil)

        let reply = await coordinator.send("Start today's workout")

        #expect(reply.isError == false)
        // No auto-navigation side channel any more — the card (with its own
        // "Start Now" button) is the only way the athlete actually starts it.
        let messages = try ctx.fetch(FetchDescriptor<ChatMessageModel>(sortBy: [SortDescriptor(\.timestamp)]))
        let cardMessage = try #require(messages.first { $0.cardKind == .startWorkout })
        let payload = try #require(cardMessage.decodedCardPayload(as: StartWorkoutCardPayload.self))
        #expect(payload.plannedSessionID == sessionID)
    }

    /// `regenerate_plan` can't await inside the synchronous tool call, so the
    /// coordinator does the actual generation itself after the tool loop
    /// finishes — with no active provider, `generateAndStore` falls back to
    /// the rule engine. The status lives on its own `.planRegeneration` card,
    /// inserted `.pending` and settled to `.succeeded` once generation
    /// finishes — not appended onto the reply's own text.
    @Test func sendExecutesRegeneratePlanToolAndSettlesARegenerationCard() async throws {
        let ctx = ModelContext(try container())
        let profile = UserProfile(
            goalRaw: "buildMuscle", experienceRaw: "intermediate", heightCm: 178, weightKg: 75,
            birthYear: 2000, sexRaw: "male", sessionsPerWeek: 4, sessionLengthMinutes: 60,
            availableEquipmentRaws: ["barbell"], excludedMuscleRaws: [], excludedExerciseIDs: [])
        ctx.insert(profile)
        try ctx.save()
        let toolTurn = """
        {"decision":"tool_call","toolCall":{"name":"regenerate_plan","argsJSON":"{\\"reason\\": \\"switch to 5 days\\"}"}}
        """
        let finalTurn = """
        {"decision":"final","final":{"reply":"On it, rebuilding your plan."}}
        """
        let provider = StubLLMProvider(responses: [.success(toolTurn), .success(finalTurn)])
        let coordinator = AskCoachCoordinator(catalog: catalog(), context: ctx, provider: provider, activeProfile: nil)

        let reply = await coordinator.send("I want to switch to 5 days a week")

        #expect(reply.isError == false)
        // The reply is exactly the model's own text now — no appended note.
        #expect(reply.text == "On it, rebuilding your plan.")
        let plans = try ctx.fetch(FetchDescriptor<StoredPlan>())
        #expect(!plans.isEmpty)
        let messages = try ctx.fetch(FetchDescriptor<ChatMessageModel>(sortBy: [SortDescriptor(\.timestamp)]))
        let cardMessage = try #require(messages.first { $0.cardKind == .planRegeneration })
        let payload = try #require(cardMessage.decodedCardPayload(as: PlanRegenerationCardPayload.self))
        #expect(payload.status == .succeeded)
        #expect(payload.detail == "Coach updated (rule engine)")
    }

    /// Memory extraction used to be a second, separately-billed round trip
    /// through `MemoryKeeperCoordinator` after every chat message. It's now
    /// folded into this same reply call's own JSON — no second call, no
    /// second `AICallRecord`.
    @Test func sendAppliesMemoryCandidatesFromTheSameReplyCallWithNoSecondCall() async throws {
        let ctx = ModelContext(try container())
        let finalTurn = """
        {"decision":"final","final":{
          "reply":"Noted, I'll favor dumbbell presses.",
          "memoryCandidates":[{"kind":"preference","statement":"Prefers dumbbells over barbells.",
            "action":null,"exerciseID":null,"muscle":null,"equipment":"dumbbell",
            "freeTags":[],"relation":"new","relatedMemoryID":null}],
          "measurementCandidates":[]
        }}
        """
        let provider = StubLLMProvider(responses: [.success(finalTurn)])
        let coordinator = AskCoachCoordinator(catalog: catalog(), context: ctx, provider: provider, activeProfile: nil)

        let reply = await coordinator.send("I like dumbbells more than barbells for pressing")

        #expect(reply.isError == false)
        let memories = try ctx.fetch(FetchDescriptor<CoachMemoryModel>())
        #expect(memories.count == 1)
        #expect(memories[0].kindRaw == "preference")
        let calls = try ctx.fetch(FetchDescriptor<AICallRecord>())
        #expect(calls.count == 1)
        #expect(calls[0].callType == "askCoach")
    }

    @Test func providerFailureReturnsErrorMessageButKeepsUserMessage() async throws {
        let ctx = ModelContext(try container())
        let provider = StubLLMProvider(responses: [.failure(.emptyResponse)])
        let coordinator = AskCoachCoordinator(catalog: catalog(), context: ctx, provider: provider, activeProfile: nil)

        let reply = await coordinator.send("test message")

        #expect(!reply.text.isEmpty)
        #expect(reply.isError == true)
        let messages = try ctx.fetch(FetchDescriptor<ChatMessageModel>())
        #expect(messages.count == 1) // the user's message is never lost, per design spec §3
        #expect(messages[0].role == "user")
    }
}
