import FitnessDomain

extension UserProfile {
    /// Converts the persisted onboarding answers into the plain `FitnessCore`
    /// planning input. Unknown raw strings fall back safely:
    /// unknown goal → `.generalFitness`, unknown experience → `.beginner`,
    /// unmappable equipment/muscle strings are dropped.
    func makeUserContext() -> UserContext {
        UserContext(
            goal: Goal(rawValue: goalRaw) ?? .generalFitness,
            experience: ExperienceLevel(rawValue: experienceRaw) ?? .beginner,
            sessionsPerWeek: sessionsPerWeek,
            sessionLengthMinutes: sessionLengthMinutes,
            availableEquipment: Set(availableEquipmentRaws.compactMap(Equipment.init(rawValue:))),
            excludedExerciseIDs: Set(excludedExerciseIDs),
            excludedMuscles: Set(excludedMuscleRaws.compactMap(MuscleGroup.init(rawValue:)))
        )
    }
}
