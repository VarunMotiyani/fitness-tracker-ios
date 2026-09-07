public enum Goal: String, Codable, Sendable, CaseIterable {
    case loseFat, buildMuscle, getStronger, generalFitness
}

public enum ExperienceLevel: String, Codable, Sendable, CaseIterable {
    case beginner, intermediate, advanced
}

public enum MuscleGroup: String, Codable, Sendable, CaseIterable {
    case chest, back, lowerBack, traps, shoulders
    case biceps, triceps, forearms
    case quads, hamstrings, glutes, calves
    case abs
}

/// Equipment vocabulary, sized to what the bundled catalogs actually distinguish — the
/// union of Gym Visual's 28 raw equipment strings and free-exercise-db's 12. The
/// original 9 cases (barbell...other) collapsed everything past the basics into `other`;
/// these additions recover the equipment categories with real substitution value (a
/// smith machine and a leverage machine are both "machine" but not interchangeable when
/// checking what a home gym actually has).
public enum Equipment: String, Codable, Sendable, CaseIterable {
    case barbell, dumbbell, cable, machine, bodyweight, kettlebell, bands, ezBar
    case smithMachine, leverageMachine, stabilityBall, medicineBall, sled, rope, roller, cardioMachine
    case other
}

public enum Mechanic: String, Codable, Sendable {
    case compound, isolation, unknown
}

public enum ForceType: String, Codable, Sendable {
    case push, pull
    case `static`
}

public enum Difficulty: String, Codable, Sendable {
    case beginner, intermediate, expert
}

public enum WeightUnit: String, Codable, Sendable, CaseIterable {
    case kg, lb
}

public typealias MassUnit = WeightUnit

