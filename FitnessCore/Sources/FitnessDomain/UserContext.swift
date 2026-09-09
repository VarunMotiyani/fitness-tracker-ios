public struct UserContext: Sendable, Equatable {
    public let goal: Goal
    public let experience: ExperienceLevel
    public let sessionsPerWeek: Int
    /// Optional explicit split style. Nil keeps the experience/day-count auto selector.
    public let splitTemplateName: String?
    public let sessionLengthMinutes: Int
    public let availableEquipment: Set<Equipment>
    public let excludedExerciseIDs: Set<String>
    public let excludedMuscles: Set<MuscleGroup>

    public init(goal: Goal,
                experience: ExperienceLevel,
                sessionsPerWeek: Int,
                splitTemplateName: String? = nil,
                sessionLengthMinutes: Int,
                availableEquipment: Set<Equipment>,
                excludedExerciseIDs: Set<String>,
                excludedMuscles: Set<MuscleGroup>) {
        self.goal = goal
        self.experience = experience
        self.sessionsPerWeek = sessionsPerWeek
        self.splitTemplateName = splitTemplateName
        self.sessionLengthMinutes = sessionLengthMinutes
        self.availableEquipment = availableEquipment
        self.excludedExerciseIDs = excludedExerciseIDs
        self.excludedMuscles = excludedMuscles
    }

    /// Source-compatible initializer retained for existing callers and persisted-plan tests.
    public init(goal: Goal,
                experience: ExperienceLevel,
                sessionsPerWeek: Int,
                sessionLengthMinutes: Int,
                availableEquipment: Set<Equipment>,
                excludedExerciseIDs: Set<String>,
                excludedMuscles: Set<MuscleGroup>) {
        self.init(goal: goal, experience: experience, sessionsPerWeek: sessionsPerWeek,
                  splitTemplateName: nil, sessionLengthMinutes: sessionLengthMinutes,
                  availableEquipment: availableEquipment, excludedExerciseIDs: excludedExerciseIDs,
                  excludedMuscles: excludedMuscles)
    }
}
