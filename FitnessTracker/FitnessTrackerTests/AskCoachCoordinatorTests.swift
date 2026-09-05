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
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func exercise(_ id: String) -> Exercise {
        Exercise(id: id, name: id, primaryMuscle: .chest, secondaryMuscles: [],
                 equipment: .barbell, mechanic: .compound, force: .push,
                 difficulty: .intermediate, isUnilateral: false, instructions: [], imagePaths: [])
    }

    private func catalog() -> CatalogStore { CatalogStore(exercises: [exercise("bench")]) }

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
