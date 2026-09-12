import Foundation
import FitnessDomain

/// Derives a human day name ("Push Day") from the muscle groups a session
/// actually targets. Replaces the old demo-catalog exercise-ID mapping
/// ("0025" == Push Day), which silently mislabelled every real plan.
enum RoutineNaming {
    static func dayName(for focusMuscles: [MuscleGroup]) -> String {
        let push: Set<MuscleGroup> = [.chest, .shoulders, .triceps]
        let pull: Set<MuscleGroup> = [.back, .lowerBack, .traps, .biceps, .forearms]
        let legs: Set<MuscleGroup> = [.quads, .hamstrings, .glutes, .calves]

        let muscles = Set(focusMuscles)
        let scores: [(name: String, score: Int)] = [
            ("Push Day", muscles.intersection(push).count),
            ("Pull Day", muscles.intersection(pull).count),
            ("Leg Day", muscles.intersection(legs).count),
        ]
        guard let best = scores.max(by: { $0.score < $1.score }), best.score > 0 else {
            return "Workout"
        }
        let tied = scores.filter { $0.score == best.score }.count
        guard tied == 1 else { return "Full Body" }
        return best.name
    }
}
