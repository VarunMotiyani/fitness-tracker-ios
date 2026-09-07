import Foundation
import LLMKit

nonisolated struct ChatSummaryDTO: Codable, Sendable {
    let summary: String
}

nonisolated enum ChatSummaryPromptBuilder {
    static let finalSchema = JSONSchema(json: """
    {"summary": "string"}
    """)

    static func system() -> String {
        """
        You maintain a running summary of a coaching conversation so far. \
        Given the existing summary (if any) and a batch of older messages \
        being folded in, produce ONE updated summary paragraph that preserves \
        every concrete fact (injuries, preferences, goals, numbers mentioned) \
        and drops small talk. Respond only in the required JSON shape.
        """
    }

    static func user(existingSummary: String, messages: [(role: String, text: String)]) -> String {
        let summarySection = existingSummary.isEmpty ? "No summary yet." : "Existing summary:\n\(existingSummary)"
        let messagesSection = messages.map { "\($0.role): \($0.text)" }.joined(separator: "\n")
        return "\(summarySection)\n\nMessages to fold in:\n\(messagesSection)\n\nProduce the updated summary."
    }
}
