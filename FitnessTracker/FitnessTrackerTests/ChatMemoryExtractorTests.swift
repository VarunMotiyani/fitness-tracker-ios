import Testing
import SwiftData
import Foundation
import FitnessDomain
import CoachMemory
import LLMKit
@testable import FitnessTracker

@MainActor
@Suite struct ChatMemoryExtractorTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: UserProfile.self, StoredPlan.self, ProviderProfile.self, AICallRecord.self,
            CompletedSessionModel.self, CompletedEntryModel.self, LoggedSetModel.self,
            BodyweightEntryModel.self, DailyCheckinModel.self, ObservationModel.self,
            PersonalRecordModel.self, CoachMemoryModel.self,
            ChatMessageModel.self, ChatSummaryModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func trivialGreetingsSkippedWithoutCallingProvider() async throws {
        let cont = try container()
        let ctx = ModelContext(cont)
        let convID = UUID().uuidString

        ctx.insert(ChatMessageModel(role: "user", text: "hi coach", conversationID: convID))
        ctx.insert(ChatMessageModel(role: "assistant", text: "Hey! How's your training going?", conversationID: convID))
        ctx.insert(ChatMessageModel(role: "user", text: "thanks!", conversationID: convID))

        // Stub provider with no responses — if called, it would fail or throw
        let provider = StubLLMProvider(responses: [])
        let extractor = ChatMemoryExtractor(
            context: ctx,
            provider: provider,
            activeProfile: nil,
            conversationID: convID
        )

        await extractor.extractMemoriesIfNeeded()

        let memories = try ctx.fetch(FetchDescriptor<CoachMemoryModel>())
        #expect(memories.isEmpty)
        let callRecords = try ctx.fetch(FetchDescriptor<AICallRecord>())
        #expect(callRecords.isEmpty)
    }

    @Test func substantiveConversationExtractsConstraintMemory() async throws {
        let cont = try container()
        let ctx = ModelContext(cont)
        let convID = UUID().uuidString

        ctx.insert(ChatMessageModel(
            role: "user",
            text: "My left knee has been hurting whenever I do heavy squats, please avoid heavy back squats for now",
            conversationID: convID
        ))
        ctx.insert(ChatMessageModel(
            role: "assistant",
            text: "Understood, I will avoid prescribing heavy back squats and focus on joint-friendly quad work.",
            conversationID: convID
        ))

        let finalTurn = """
        {"decision":"final","final":{
          "memoryCandidates":[{"kind":"constraint","statement":"Left knee hurts on heavy squats; avoid heavy back squats.",
            "action":"Avoid heavy barbell back squats","exerciseID":null,"muscle":"quads","equipment":null,
            "freeTags":[],"relation":"new","relatedMemoryID":null}],
          "measurementCandidates":[]
        }}
        """
        let provider = StubLLMProvider(responses: [.success(finalTurn)])
        let extractor = ChatMemoryExtractor(
            context: ctx,
            provider: provider,
            activeProfile: nil,
            conversationID: convID
        )

        await extractor.extractMemoriesIfNeeded()

        let memories = try ctx.fetch(FetchDescriptor<CoachMemoryModel>())
        #expect(memories.count == 1)
        #expect(memories[0].statement == "Left knee hurts on heavy squats; avoid heavy back squats.")
        #expect(memories[0].kindRaw == "constraint")
        #expect(memories[0].action == "Avoid heavy barbell back squats")

        let callRecords = try ctx.fetch(FetchDescriptor<AICallRecord>())
        #expect(callRecords.count == 1)
        #expect(callRecords[0].callType == "chatMemoryExtract")
    }

    @Test func measurementCandidatePersistedAsObservation() async throws {
        let cont = try container()
        let ctx = ModelContext(cont)
        let convID = UUID().uuidString

        ctx.insert(ChatMessageModel(
            role: "user",
            text: "Weighed in at 81.5 kg this morning after waking up",
            conversationID: convID
        ))
        ctx.insert(ChatMessageModel(
            role: "assistant",
            text: "Great, logging your weight at 81.5 kg.",
            conversationID: convID
        ))

        let finalTurn = """
        {"decision":"final","final":{
          "memoryCandidates":[],
          "measurementCandidates":[{"kind":"bodyweight","value":81.5,"unit":"kg"}]
        }}
        """
        let provider = StubLLMProvider(responses: [.success(finalTurn)])
        let extractor = ChatMemoryExtractor(
            context: ctx,
            provider: provider,
            activeProfile: nil,
            conversationID: convID
        )

        await extractor.extractMemoriesIfNeeded()

        let observations = try ctx.fetch(FetchDescriptor<ObservationModel>())
        #expect(observations.count == 1)
        #expect(observations[0].kind == "bodyweight")
        #expect(observations[0].value == 81.5)
        #expect(observations[0].unit == "kg")
    }

    @Test func alreadyExtractedConversationIsNotProcessedTwice() async throws {
        let cont = try container()
        let ctx = ModelContext(cont)
        let convID = UUID().uuidString

        ctx.insert(ChatMessageModel(
            role: "user",
            text: "I prefer dumbbell chest exercises over barbell",
            conversationID: convID
        ))

        let finalTurn = """
        {"decision":"final","final":{
          "memoryCandidates":[{"kind":"preference","statement":"Prefers dumbbell chest exercises.",
            "action":null,"exerciseID":null,"muscle":"chest","equipment":"dumbbell",
            "freeTags":[],"relation":"new","relatedMemoryID":null}],
          "measurementCandidates":[]
        }}
        """
        // Provider only has 1 response: second call would fail if attempted
        let provider = StubLLMProvider(responses: [.success(finalTurn)])
        let extractor = ChatMemoryExtractor(
            context: ctx,
            provider: provider,
            activeProfile: nil,
            conversationID: convID
        )

        await extractor.extractMemoriesIfNeeded()

        let memoriesFirstPass = try ctx.fetch(FetchDescriptor<CoachMemoryModel>())
        #expect(memoriesFirstPass.count == 1)

        // Second pass should early-exit via isAlreadyExtracted
        await extractor.extractMemoriesIfNeeded()

        let memoriesSecondPass = try ctx.fetch(FetchDescriptor<CoachMemoryModel>())
        #expect(memoriesSecondPass.count == 1)
    }
}

