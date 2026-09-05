import Foundation
import FitnessDomain
import Metrics
import LLMKit

nonisolated enum MemoryKeeperPromptBuilder {
    /// "bodyweight (kg), bodyFatPercent (%), muscleMassKg (kg)" — built from
    /// `MeasurementGuardrail`'s own vocabulary so this prompt can never drift
    /// from what the guardrail actually accepts.
    private static let measurementKindVocabulary: String = MeasurementGuardrail.knownKinds
        .map { kind in "\(kind) (\(MeasurementGuardrail.expectedUnit(for: kind) ?? "?"))" }
        .joined(separator: ", ")

    static var finalSchema: JSONSchema {
        let kindEnum = MeasurementGuardrail.knownKinds.joined(separator: "|")
        return JSONSchema(json: """
        {
          "memoryCandidates": [{"kind": "preference|constraint|observation|goal|responsePattern",
                                "statement": "string", "action": "string|null",
                                "exerciseID": "string|null", "muscle": "string|null",
                                "equipment": "string|null", "freeTags": ["string"],
                                "relation": "new|reinforces|contradicts", "relatedMemoryID": "string|null"}],
          "measurementCandidates": [{"kind": "\(kindEnum)", "value": "number", "unit": "string"}]
        }
        """)
    }

    /// The persona is the same coach voice as `FinalizePromptBuilder`, but the
    /// job here is purely observational — this call never changes anything,
    /// it only notices and remembers.
    static func system() -> String {
        """
        You are an experienced, direct personal trainer reviewing a session \
        that just finished. You do not change anything about it — you only \
        decide what, if anything, is worth remembering for future sessions.

        Return two arrays:
        - memoryCandidates: durable facts about this athlete worth carrying \
        forward — a stated preference, an injury or hard constraint, a \
        recurring pattern, a goal, or a notable observation. Most sessions \
        produce none; an empty array is a normal, expected answer, not a \
        failure. Set "relation" to "new" for a fact you haven't seen before, \
        "reinforces" (with "relatedMemoryID") when it confirms an existing \
        memory you were given, or "contradicts" (with "relatedMemoryID") when \
        it supersedes one. The bracketed ID shown before each fact under \
        "what you already know about this athlete" is exactly what you should \
        pass back as "relatedMemoryID".
        - measurementCandidates: only an explicit numeric body-composition \
        measurement the athlete reported in their notes (e.g. an InBody scan \
        result) — never a number you calculated yourself, and never a set/rep/ \
        load figure from the workout itself. "kind" must be one of: \
        \(measurementKindVocabulary) — and "unit" must exactly match the unit \
        shown for that kind.

        Only extract what is actually stated. Do not infer an injury from a \
        single hard set, and do not invent a preference from one exercise \
        choice. Respond only in the required JSON shape.
        """
    }

    static func user(
        session: CompletedSessionSnapshot,
        checkin: DailyCheckinSnapshot?,
        memoryDigest: String
    ) -> String {
        let noteSection = session.overallNote.map { "Athlete's note on today's session: \($0)" }
            ?? "No note left on today's session."

        let checkinSection = checkin.map { c -> String in
            var lines = ["Today's check-in:"]
            if let sleep = c.sleepQuality { lines.append("- Sleep quality: \(sleep)/10") }
            if let soreness = c.soreness { lines.append("- Soreness: \(soreness)/10") }
            if let note = c.note, !note.isEmpty { lines.append("- Note: \(note)") }
            return lines.joined(separator: "\n")
        } ?? ""

        let memorySection = memoryDigest.isEmpty
            ? "No standing memory yet for this athlete."
            : "What you already know about this athlete:\n\(memoryDigest)"

        var outcomeLine = "Session outcome: \(session.outcome), energy: \(session.energy), " +
            "duration: \(session.actualDurationMin)/\(session.plannedDurationMin) min."
        if let partialReason = session.partialReason {
            outcomeLine += " Partial reason: \(partialReason)."
        }

        let entriesSection = session.entries.isEmpty ? "" : "What was actually logged:\n" +
            session.entries.map { entry -> String in
                var line = "- \(entry.exerciseID): \(entry.sets.count) sets"
                if let feel = entry.feel { line += ", feel: \(feel)" }
                if entry.skipped { line += ", skipped" }
                if let note = entry.note, !note.isEmpty { line += " — note: \(note)" }
                return line
            }.joined(separator: "\n")

        let sections = [
            outcomeLine,
            noteSection,
            entriesSection,
            checkinSection,
            memorySection,
            "Decide what, if anything, is worth remembering from this session."
        ].filter { !$0.isEmpty }

        return sections.joined(separator: "\n\n")
    }
}
