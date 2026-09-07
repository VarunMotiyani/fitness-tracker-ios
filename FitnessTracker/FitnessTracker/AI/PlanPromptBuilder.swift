import Foundation
import FitnessDomain
import ExerciseCatalog
import RuleEngine

nonisolated struct PlanPromptBuilder {
    let catalog: CatalogStore

    init(catalog: CatalogStore) { self.catalog = catalog }

    func system() -> String {
        """
        You are a strength & physique coach. Build one week of training.
        Hard rules:
        - Use ONLY the exercise IDs listed in the user message. Never invent an ID.
        - Keep each muscle's weekly working sets within the min–max hints given.
        - Give every session a non-empty item list.
        - Respond with a single JSON object matching the provided schema. No prose, no markdown, no code fences.
        """
    }

    func user(context: UserContext, priorIssues: [String] = [], memoryDigest: String = "") -> String {
        let inScopeMuscles = MuscleGroup.allCases.filter { !context.excludedMuscles.contains($0) }

        let slice = catalog.all
            .filter { context.availableEquipment.contains($0.equipment) }
            .filter { !context.excludedExerciseIDs.contains($0.id) }
            .filter { !context.excludedMuscles.contains($0.primaryMuscle) }
            .sorted { $0.id < $1.id }
            .map { "\($0.id) | \($0.name) | \($0.primaryMuscle.rawValue) | \($0.equipment.rawValue) | \($0.mechanic.rawValue)" }
            .joined(separator: "\n")

        let landmarks = inScopeMuscles.map { m -> String in
            let b = VolumeLandmarks.band(for: m, experience: context.experience)
            return "\(m.rawValue): \(b.mev)–\(b.mrv) sets/week (aim ~\(b.mav))"
        }.joined(separator: "\n")

        var out = """
        Goal: \(context.goal.rawValue)
        Experience: \(context.experience.rawValue)
        Sessions per week: \(context.sessionsPerWeek)
        Session length: \(context.sessionLengthMinutes) minutes

        Available exercises (ID | name | primary muscle | equipment | mechanic):
        \(slice)

        Weekly volume hints:
        \(landmarks)
        """

        if !priorIssues.isEmpty {
            out += "\n\nYour previous attempt had these problems — fix all of them:\n"
            out += priorIssues.map { "- \($0)" }.joined(separator: "\n")
        }
        if !memoryDigest.isEmpty {
            out += "\n\nWhat you know about this athlete:\n\(memoryDigest)"
        }
        return out
    }
}
