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
        program directly yourself — you can only propose changes for the \
        athlete to review.

        You now have tools to propose a concrete change to an UPCOMING \
        session (one that hasn't started yet): propose_exercise_swap and \
        propose_set_change. Use get_upcoming_sessions first to find the \
        right plannedSessionID — never guess one. Every proposal becomes a \
        card the athlete taps to accept or skip; you never change anything \
        directly. If they're asking about the session they're currently in, \
        tell them to use the swap/adjust controls in the session screen \
        instead — your proposals can only reach a session that hasn't started.

        For a permanent program change — not a single session — use \
        propose_routine_revision instead; it becomes a standing preference \
        that shapes future plans, not an immediate edit.

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
