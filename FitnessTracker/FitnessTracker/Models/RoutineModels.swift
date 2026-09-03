import Foundation
import FitnessDomain
import ExerciseCatalog

public struct ExerciseConfig: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var exerciseID: String
    public var sets: Int
    public var reps: Int
    public var repsMin: Int?
    public var repsMax: Int?
    public var weightKg: Double
    public var restSec: Int?
    public var mode: String // "reps", "time", "cardio"
    public var sec: Int
    public var speed: Double
    public var bodyweight: Bool
    public var perSide: Bool
    public var supersetID: String?
    public var policy: String?
    public var incKg: Double?
    public var coachNote: String

    public init(
        id: UUID = UUID(),
        exerciseID: String,
        sets: Int = 3,
        reps: Int = 10,
        repsMin: Int? = nil,
        repsMax: Int? = nil,
        weightKg: Double = 0.0,
        restSec: Int? = 90,
        mode: String = "reps",
        sec: Int = 30,
        speed: Double = 0.0,
        bodyweight: Bool = false,
        perSide: Bool = false,
        supersetID: String? = nil,
        policy: String? = nil,
        incKg: Double? = nil,
        coachNote: String = ""
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.sets = sets
        self.reps = reps
        self.repsMin = repsMin
        self.repsMax = repsMax
        self.weightKg = weightKg
        self.restSec = restSec
        self.mode = mode
        self.sec = sec
        self.speed = speed
        self.bodyweight = bodyweight
        self.perSide = perSide
        self.supersetID = supersetID
        self.policy = policy
        self.incKg = incKg
        self.coachNote = coachNote
    }

    public var isRepRange: Bool {
        repsMin != nil && repsMax != nil
    }
}

public struct RoutineDraft: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var iconName: String
    public var policy: String?
    public var excludeFromProgression: Bool
    public var exercises: [ExerciseConfig]

    public init(
        id: UUID = UUID(),
        name: String,
        iconName: String = "figure.strengthtraining.traditional",
        policy: String? = nil,
        excludeFromProgression: Bool = false,
        exercises: [ExerciseConfig] = []
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.policy = policy
        self.excludeFromProgression = excludeFromProgression
        self.exercises = exercises
    }
}

public enum StarterRoutines {
    public static func ppl() -> [RoutineDraft] {
        [
            RoutineDraft(
                name: "Push Day",
                iconName: "figure.strengthtraining.traditional",
                exercises: [
                    ExerciseConfig(exerciseID: "0025", sets: 3, reps: 8, repsMin: 6, repsMax: 10, weightKg: 60.0, restSec: 120), // Barbell Bench Press
                    ExerciseConfig(exerciseID: "0314", sets: 3, reps: 10, repsMin: 8, repsMax: 12, weightKg: 22.5, restSec: 90), // Incline Dumbbell Press
                    ExerciseConfig(exerciseID: "0334", sets: 3, reps: 12, weightKg: 10.0, restSec: 60), // Dumbbell Lateral Raise
                    ExerciseConfig(exerciseID: "0088", sets: 3, reps: 12, weightKg: 25.0, restSec: 60) // Cable Triceps Pushdown
                ]
            ),
            RoutineDraft(
                name: "Pull Day",
                iconName: "figure.core.training",
                exercises: [
                    ExerciseConfig(exerciseID: "0027", sets: 3, reps: 8, repsMin: 6, repsMax: 10, weightKg: 60.0, restSec: 120), // Barbell Bent Over Row
                    ExerciseConfig(exerciseID: "0150", sets: 3, reps: 10, weightKg: 55.0, restSec: 90), // Lat Pulldown
                    ExerciseConfig(exerciseID: "0082", sets: 3, reps: 12, weightKg: 30.0, restSec: 60), // Cable Face Pull
                    ExerciseConfig(exerciseID: "0311", sets: 3, reps: 12, weightKg: 14.0, restSec: 60) // Dumbbell Biceps Curl
                ]
            ),
            RoutineDraft(
                name: "Legs Day",
                iconName: "figure.run",
                exercises: [
                    ExerciseConfig(exerciseID: "0043", sets: 3, reps: 8, repsMin: 6, repsMax: 10, weightKg: 80.0, restSec: 120), // Barbell Squat
                    ExerciseConfig(exerciseID: "0032", sets: 3, reps: 8, weightKg: 90.0, restSec: 120), // Barbell Romanian Deadlift
                    ExerciseConfig(exerciseID: "0585", sets: 3, reps: 12, weightKg: 120.0, restSec: 90), // Leg Press
                    ExerciseConfig(exerciseID: "0584", sets: 3, reps: 15, weightKg: 40.0, restSec: 60) // Leg Extensions
                ]
            )
        ]
    }
}
