import Foundation
import LLMKit

nonisolated enum AskCoachPromptBuilder {
    static let finalSchema = JSONSchema(json: """
    {"reply": "string"}
    """)

    static func system() -> String {
        """
        You are an experienced, direct personal trainer chatting with your \
        athlete. You can look up their recovery status, muscle balance, and \
        training history using the tools available to you — never guess a \
        number a tool could give you exactly. You cannot change their \
        program from this chat; if they ask you to swap an exercise or \
        change their plan, tell them that's coming soon and answer what you \
        can about their situation instead.

        If a request is ambiguous, ask a clarifying question rather than \
        guessing what they meant. Keep replies conversational and concise — \
        this is a chat, not a report. Respond only in the required JSON shape.
        """
    }

    static func user(
        recentMessages: [(role: String, text: String)],
        summary: String,
        memoryDigest: String,
        newMessage: String
    ) -> String {
        let summarySection = summary.isEmpty ? "" : "Earlier in this conversation:\n\(summary)"
        let recentSection = recentMessages.isEmpty ? "" : recentMessages.map { "\($0.role): \($0.text)" }.joined(separator: "\n")
        let memorySection = memoryDigest.isEmpty
            ? ""
            : "What you know about this athlete:\n\(memoryDigest)"

        let sections = [summarySection, recentSection, memorySection, "athlete: \(newMessage)"]
            .filter { !$0.isEmpty }
        return sections.joined(separator: "\n\n")
    }
}
