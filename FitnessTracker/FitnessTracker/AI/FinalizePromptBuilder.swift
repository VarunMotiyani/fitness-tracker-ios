import Foundation
import FitnessDomain
import ExerciseCatalog
import LLMKit

nonisolated enum FinalizePromptBuilder {
    static let finalSchema = JSONSchema(json: """
    {
      "items": [{"exerciseID": "string", "targetSets": "number", "targetRepsMin": "number",
                 "targetRepsMax": "number", "targetLoadKg": "number|null", "restSeconds": "number"}],
      "perItemRationale": {"exerciseID": "one short sentence, citing a specific number from context"}
    }
    """)

    /// The persona and the hard rules — shared across every call this
    /// prompt builder produces, so the coach reads as one consistent voice.
    /// The "constraint" language matches design spec §8's hard-filter rule
    /// verbatim so a reviewer can grep for it.
    static func system() -> String {
        """
        You are an experienced, direct personal trainer. You finalize today's \
        workout session: you may adjust sets, reps, and load per exercise, and \
        you may use the tools available to you to check recovery, look up \
        history, or verify your math — never compute an exact number yourself \
        when a tool exists for it.

        Hard rules, not preferences:
        - Any memory tagged as a constraint (an injury, a hard equipment limit) \
        is non-negotiable. Never propose an exercise or load that violates one.
        - Every load or set change must be plausible given the athlete's actual \
        recent performance — use check_progression to verify before proposing \
        a jump, if that tool is available to you.
        - Every rationale must cite a specific number or fact from the context \
        you were given or a tool result. Generic encouragement with no \
        specific reference is not acceptable.
        - If time available is tight, prefer trimming sets over dropping an \
        exercise's stimulus to zero.

        Respond only in the required JSON shape.
        """
    }

    static func user(
        session: PlannedSession,
        catalog: CatalogStore,
        memoryDigest: String,
        energyLabel: String,
        timeAvailableMin: Int
    ) -> String {
        let itemLines = session.items.map { item -> String in
            let name = catalog.exercise(id: item.exerciseID)?.name ?? item.exerciseID
            let loadText = item.targetLoadKg.map { "\($0) kg" } ?? "no logged load"
            return "- \(name) (\(item.exerciseID)): \(item.targetSets) sets, \(item.targetReps.min)-\(item.targetReps.max) reps, \(loadText), rest \(item.restSeconds)s"
        }.joined(separator: "\n")

        let memorySection = memoryDigest.isEmpty
            ? "No standing memory yet for this athlete."
            : "What you know about this athlete:\n\(memoryDigest)"

        return """
        Today's planned session:
        \(itemLines)

        \(memorySection)

        Energy today: \(energyLabel)
        Time available: \(timeAvailableMin) minutes

        Finalize this session for today.
        """
    }
}
