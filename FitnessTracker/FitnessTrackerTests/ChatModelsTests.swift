import Testing
import SwiftData
@testable import FitnessTracker

@Suite struct ChatModelsTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: ChatMessageModel.self, ChatSummaryModel.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func chatMessageDefaultsAndRoundTrips() throws {
        let ctx = ModelContext(try container())
        let msg = ChatMessageModel(role: "user", text: "How's my recovery?")
        ctx.insert(msg)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<ChatMessageModel>())
        #expect(fetched.count == 1)
        #expect(fetched[0].role == "user")
        #expect(fetched[0].text == "How's my recovery?")
    }

    @Test func chatSummaryDefaultsToEmpty() throws {
        let ctx = ModelContext(try container())
        let summary = ChatSummaryModel()
        ctx.insert(summary)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<ChatSummaryModel>())
        #expect(fetched.count == 1)
        #expect(fetched[0].text.isEmpty)
        #expect(fetched[0].messagesCoveredThrough == nil)
    }
}
