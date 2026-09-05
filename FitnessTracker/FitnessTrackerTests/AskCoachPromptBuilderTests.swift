import Testing
import Foundation
@testable import FitnessTracker

@Suite struct AskCoachPromptBuilderTests {
    @Test func systemPromptStatesReadOnlyConstraint() {
        let prompt = AskCoachPromptBuilder.system()
        #expect(prompt.lowercased().contains("cannot") || prompt.lowercased().contains("does not change"))
    }

    @Test func userPromptIncludesNewMessage() {
        let prompt = AskCoachPromptBuilder.user(recentMessages: [], summary: "", memoryDigest: "", newMessage: "How's my recovery?")
        #expect(prompt.contains("How's my recovery?"))
    }

    @Test func userPromptIncludesRecentMessages() {
        let prompt = AskCoachPromptBuilder.user(
            recentMessages: [("user", "I hurt my shoulder"), ("assistant", "Noted, avoiding overhead work.")],
            summary: "", memoryDigest: "", newMessage: "What should I do instead?"
        )
        #expect(prompt.contains("I hurt my shoulder"))
        #expect(prompt.contains("avoiding overhead work"))
    }

    @Test func userPromptIncludesSummaryWhenPresent() {
        let prompt = AskCoachPromptBuilder.user(recentMessages: [], summary: "Athlete has a history of shoulder soreness.", memoryDigest: "", newMessage: "test")
        #expect(prompt.contains("shoulder soreness"))
    }

    @Test func userPromptOmitsSummarySectionWhenEmpty() {
        let prompt = AskCoachPromptBuilder.user(recentMessages: [], summary: "", memoryDigest: "", newMessage: "test")
        #expect(!prompt.contains("Earlier in this conversation"))
    }
}
