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
            StoredPlan.self, PendingCoachSuggestion.self,
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
