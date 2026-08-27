public struct UserContext: Sendable, Equatable {
    public let goal: Goal
    public let experience: ExperienceLevel
    public let sessionsPerWeek: Int
    public let sessionLengthMinutes: Int
    public let availableEquipment: Set<Equipment>
    public let excludedExerciseIDs: Set<String>
    public let excludedMuscles: Set<MuscleGroup>

    public init(goal: Goal,
                experience: ExperienceLevel,
                sessionsPerWeek: Int,
                sessionLengthMinutes: Int,
                availableEquipment: Set<Equipment>,
                excludedExerciseIDs: Set<String>,
                excludedMuscles: Set<MuscleGroup>) {
        self.goal = goal
        self.experience = experience
        self.sessionsPerWeek = sessionsPerWeek
        self.sessionLengthMinutes = sessionLengthMinutes
        self.availableEquipment = availableEquipment
        self.excludedExerciseIDs = excludedExerciseIDs
        self.excludedMuscles = excludedMuscles
    }
}
