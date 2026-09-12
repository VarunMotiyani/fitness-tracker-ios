import Testing
import SwiftData
@testable import FitnessTracker

@MainActor
struct ChatConversationTests {
    @Test func messagesAndSummariesCarryConversationIdentity() {
        let message = ChatMessageModel(role: "user", text: "hello", conversationID: "chat-a")
        let summary = ChatSummaryModel(conversationID: "chat-a")

        #expect(message.conversationID == "chat-a")
        #expect(summary.conversationID == "chat-a")
        #expect(message.conversationID != "chat-b")
    }
}
