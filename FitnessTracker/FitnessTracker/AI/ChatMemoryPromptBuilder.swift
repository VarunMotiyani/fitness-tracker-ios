import Foundation
import LLMKit

/// Same output contract as `MemoryKeeperPromptBuilder` (reuses its
/// `finalSchema`/`MemoryKeeperDTO`) — only the persona text differs, since
/// this call reviews a chat exchange, not a finished session.
nonisolated enum ChatMemoryPromptBuilder {
    static func system() -> String {
        """
        You are an experienced, direct personal trainer reviewing something \
        the athlete just said in chat. You do not change anything — you only \
        decide what, if anything, is worth remembering for future sessions.

        Return two arrays:
        - memoryCandidates: durable facts worth carrying forward — a stated \
        preference, an injury or hard constraint, a recurring pattern, a \
        goal, or a notable observation. Most exchanges produce none; an \
        empty array is a normal, expected answer, not a failure. Set \
        "relation" to "new" for a fact you haven't seen before, "reinforces" \
        (with "relatedMemoryID") when it confirms an existing memory you \
        were given, or "contradicts" (with "relatedMemoryID") when it \
        supersedes one. The bracketed ID shown before each fact under "what \
        you already know about this athlete" is exactly what you should \
        pass back as "relatedMemoryID".
        - measurementCandidates: only an explicit numeric body-composition \
        measurement the athlete reported (e.g. an InBody scan result) — \
        never a number you calculated yourself.

        Only extract what is actually stated. Respond only in the required \
        JSON shape.
        """
    }

    static func user(userMessage: String, assistantReply: String, memoryDigest: String) -> String {
        let memorySection = memoryDigest.isEmpty
            ? "No standing memory yet for this athlete."
            : "What you already know about this athlete:\n\(memoryDigest)"

        return """
        The athlete said: \(userMessage)

        The coach replied: \(assistantReply)

        \(memorySection)

        Decide what, if anything, is worth remembering from this exchange.
        """
    }
}
