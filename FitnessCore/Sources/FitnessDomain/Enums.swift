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

public enum Equipment: String, Codable, Sendable, CaseIterable {
    case barbell, dumbbell, cable, machine, bodyweight, kettlebell, bands, ezBar, other
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

