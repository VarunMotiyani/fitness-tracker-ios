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

        When a propose_* call is driven by something you remember about this \
        athlete — a `[uuid]` line in the memory list — pass that uuid as \
        `sourceMemoryId` so the coach can learn whether that suggestion landed.

        For a permanent program change — not a single session — use \
        propose_routine_revision instead; it becomes a standing preference \
        that shapes future plans, not an immediate edit.

        If a request is ambiguous, ask a clarifying question rather than \
        guessing what they meant — but put that question in the `reply` field \
        of the final JSON, never as plain text.

        Keep replies conversational and concise — this is a chat, not a \
        report. EVERY response, including a clarifying question or a refusal, \
        must be the JSON object the schema requires: \
        {"decision":"final","final":{"reply":"..."}} or a tool call. Never \
        answer with bare prose.
        """
    }

    static func user(
        recentMessages: [(role: String, text: String)],
        summary: String,
        memoryDigest: String,
        equipmentSummary: String = "",
        newMessage: String
    ) -> String {
        let summarySection = summary.isEmpty ? "" : "Earlier in this conversation:\n\(summary)"
        let recentSection = recentMessages.isEmpty ? "" : recentMessages.map { "\($0.role): \($0.text)" }.joined(separator: "\n")
        let memorySection = memoryDigest.isEmpty
            ? ""
            : "What you know about this athlete:\n\(memoryDigest)"
        let equipmentSection = equipmentSummary.isEmpty
            ? ""
            : "Equipment the athlete has: \(equipmentSummary). Don't propose anything that needs equipment not on this list."

        let sections = [summarySection, recentSection, memorySection, equipmentSection, "athlete: \(newMessage)"]
            .filter { !$0.isEmpty }
        return sections.joined(separator: "\n\n")
    }
}
