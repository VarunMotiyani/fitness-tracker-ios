import Testing
import SwiftData
import Foundation
import LLMKit
@testable import FitnessTracker

@MainActor
@Suite struct ChatSummarizerTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: ChatMessageModel.self, ChatSummaryModel.self, AICallRecord.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func insertMessages(_ count: Int, into ctx: ModelContext, startingAt base: Date) {
        for i in 0..<count {
            ctx.insert(ChatMessageModel(role: i % 2 == 0 ? "user" : "assistant", text: "message \(i)", timestamp: base.addingTimeInterval(Double(i))))
        }
        try? ctx.save()
    }

    @Test func belowThresholdDoesNothing() async throws {
        let ctx = ModelContext(try container())
        insertMessages(20, into: ctx, startingAt: .now)
        let provider = StubLLMProvider(responses: [])
        let summarizer = ChatSummarizer(context: ctx, provider: provider, activeProfile: nil)

        await summarizer.summarizeIfNeeded()

        #expect(try ctx.fetch(FetchDescriptor<ChatMessageModel>()).count == 20)
        #expect(try ctx.fetch(FetchDescriptor<AICallRecord>()).isEmpty)
    }

    @Test func aboveThresholdFoldsOldestKeepsRecentTen() async throws {
        let ctx = ModelContext(try container())
        insertMessages(35, into: ctx, startingAt: .now)
        let finalTurn = """
        {"decision":"final","final":{"summary":"Athlete discussed shoulder soreness and pressing preferences."}}
        """
        let provider = StubLLMProvider(responses: [.success(finalTurn)])
        let summarizer = ChatSummarizer(context: ctx, provider: provider, activeProfile: nil)

        await summarizer.summarizeIfNeeded()

        let remaining = try ctx.fetch(FetchDescriptor<ChatMessageModel>())
        #expect(remaining.count == 10)

        let summaries = try ctx.fetch(FetchDescriptor<ChatSummaryModel>())
        #expect(summaries.count == 1)
        #expect(summaries[0].text == "Athlete discussed shoulder soreness and pressing preferences.")

        let calls = try ctx.fetch(FetchDescriptor<AICallRecord>())
        #expect(calls.count == 1)
        #expect(calls[0].callType == "chatSummarize")
    }

    @Test func noProviderIsANoOp() async throws {
        let ctx = ModelContext(try container())
        insertMessages(35, into: ctx, startingAt: .now)
        let summarizer = ChatSummarizer(context: ctx, provider: nil, activeProfile: nil)

        await summarizer.summarizeIfNeeded()

        #expect(try ctx.fetch(FetchDescriptor<ChatMessageModel>()).count == 35)
    }
}
