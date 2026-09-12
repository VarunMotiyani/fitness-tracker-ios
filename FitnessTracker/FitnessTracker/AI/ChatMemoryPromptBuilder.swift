import Foundation
import LLMKit
import Metrics
import CoachMemory

nonisolated enum ChatMemoryPromptBuilder {
    private static let measurementKindVocabulary: String = MeasurementGuardrail.knownKinds
        .map { kind in "\(kind) (\(MeasurementGuardrail.expectedUnit(for: kind) ?? "?"))" }
        .joined(separator: ", ")

    static var finalSchema: JSONSchema {
        MemoryKeeperPromptBuilder.finalSchema
    }

    static func system() -> String {
        """
        You are an experienced, attentive personal trainer reviewing a completed chat conversation with an athlete. \
        You do not change any plans or give replies — you only decide what, if anything, is worth remembering about the athlete \
        for future workouts, routine planning, and coaching.

        Return two arrays:
        - memoryCandidates: durable, actionable facts about this athlete worth carrying forward — a stated preference, an injury \
        or physical constraint, a recurring schedule habit/pattern, a fitness goal, or a notable observation.
          Most conversations produce none; an empty array is a normal, expected answer, not a failure.
          If the exchange was casual greetings, small talk, acknowledgements ("thanks", "ok"), or a one-off question without personal \
          athlete context, return an empty array.
          Set "relation" to "new" for a fact you haven't seen before, "reinforces" (with "relatedMemoryID") when it confirms an existing \
          memory you were given, or "contradicts" (with "relatedMemoryID") when it supersedes one. The bracketed ID shown before each \
          fact under "what you already know about this athlete" is exactly what you should pass back as "relatedMemoryID".
        - measurementCandidates: only an explicit numeric body-composition measurement the athlete reported in the chat (e.g. \
        "weighed 78.5 kg today" or "body fat is 14%") — never a number you calculated yourself, and never a set/rep/load number \
        from a workout. "kind" must be one of: \(measurementKindVocabulary) — and "unit" must match the unit shown for that kind.

        Only extract what is actually stated or confirmed by the athlete. Do not guess or invent facts. Respond only in the required JSON shape.
        """
    }

    static func user(
        messages: [(role: String, text: String)],
        memoryDigest: String
    ) -> String {
        let memorySection = memoryDigest.isEmpty
            ? "No standing memory yet for this athlete."
            : "What you already know about this athlete:\n\(memoryDigest)"

        let transcript = messages.map { message in
            let speaker = message.role == "user" ? "Athlete" : "Coach"
            return "\(speaker): \(message.text)"
        }.joined(separator: "\n\n")

        return """
        \(memorySection)

        Completed Conversation Transcript:
        \(transcript)
        """
    }
}

