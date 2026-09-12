import Foundation
import ExerciseCatalog
import FitnessDomain

struct ExerciseLibraryIntent: Equatable {
    enum Action: Equatable {
        case add
        case replace(existingExerciseID: String)
    }

    let date: Date
    let session: PlannedSession
    let action: Action

    func accepts(_ exercise: Exercise) -> Bool {
        let focusMuscles = Set(session.focusMuscles)

        guard !focusMuscles.isEmpty else {
            return false
        }

        return focusMuscles.contains(exercise.primaryMuscle)
            || exercise.secondaryMuscles.contains(where: focusMuscles.contains)
    }

    /// The contextual picker uses the shared taxonomy instead of session order. This keeps
    /// Push/Pull/Upper/Lower and custom sessions consistent across Home, Library, and AI.
    func acceptsForToday(_ exercise: Exercise) -> Bool {
        guard accepts(exercise) else { return false }
        let focus = WorkoutFocus.classify(muscles: Set(session.focusMuscles))
        let definition = WorkoutFocus.definition(for: focus)
        return ExerciseTaxonomy.compatibilityScore(exercise, session: definition) >= 0.35
    }

    func actionTitle(existingName: String? = nil) -> String {
        switch action {
        case .add:
            return "Add to today’s workout"
        case .replace:
            guard let existingName, !existingName.isEmpty else {
                return "Replace exercise"
            }
            return "Replace \(existingName)"
        }
    }
}
