import Foundation
import FitnessDomain

/// Mutable draft state for the onboarding flow. `@MainActor` (UI state) via the
/// target's default actor isolation.
@Observable
final class OnboardingModel {
    var goal: Goal?
    var experience: ExperienceLevel?
    var heightCm: Double = 0
    var weightKg: Double = 0
    var birthYear: Int = 0
    var sex: String = "unspecified"
    var sessionsPerWeek: Int = 4
    var sessionLengthMinutes: Int = 60
    var equipment: Set<Equipment> = []
    var excludedMuscles: Set<MuscleGroup> = []

    var isComplete: Bool {
        goal != nil && experience != nil
            && heightCm > 0 && weightKg > 0 && birthYear >= 1900
            && !equipment.isEmpty
            && (2...7).contains(sessionsPerWeek)
    }

    func makeProfile() -> UserProfile? {
        guard isComplete, let goal, let experience else { return nil }
        return UserProfile(
            goalRaw: goal.rawValue,
            experienceRaw: experience.rawValue,
            heightCm: heightCm,
            weightKg: weightKg,
            birthYear: birthYear,
            sexRaw: sex,
            sessionsPerWeek: sessionsPerWeek,
            sessionLengthMinutes: sessionLengthMinutes,
            availableEquipmentRaws: equipment.map(\.rawValue),
            excludedMuscleRaws: excludedMuscles.map(\.rawValue),
            excludedExerciseIDs: []
        )
    }
}
