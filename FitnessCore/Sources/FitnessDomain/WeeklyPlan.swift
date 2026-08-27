import Foundation

public enum PlanSource: String, Codable, Sendable {
    case ruleEngine, ai, fallback
}

public struct MuscleVolumeTarget: Codable, Sendable, Equatable {
    public let muscle: MuscleGroup
    public let targetSets: Int
    public init(muscle: MuscleGroup, targetSets: Int) {
        self.muscle = muscle
        self.targetSets = targetSets
    }
}

public struct PlannedItem: Codable, Sendable, Equatable {
    public let exerciseID: String
    public let targetSets: Int
    public let targetReps: RepRange
    public let targetLoadKg: Double?
    public let restSeconds: Int
    public let coachNote: String
    public init(exerciseID: String, targetSets: Int, targetReps: RepRange,
                targetLoadKg: Double?, restSeconds: Int, coachNote: String) {
        self.exerciseID = exerciseID
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetLoadKg = targetLoadKg
        self.restSeconds = restSeconds
        self.coachNote = coachNote
    }
}

public struct PlannedSession: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let order: Int
    public let focusMuscles: [MuscleGroup]
    public let items: [PlannedItem]
    public init(id: UUID, order: Int, focusMuscles: [MuscleGroup], items: [PlannedItem]) {
        self.id = id
        self.order = order
        self.focusMuscles = focusMuscles
        self.items = items
    }
}

public struct WeeklyPlan: Codable, Sendable, Equatable {
    public let weekStartDate: Date
    public let source: PlanSource
    public let rationale: String
    public let sessions: [PlannedSession]
    public let weeklyVolumeTargets: [MuscleVolumeTarget]
    public init(weekStartDate: Date, source: PlanSource, rationale: String,
                sessions: [PlannedSession], weeklyVolumeTargets: [MuscleVolumeTarget]) {
        self.weekStartDate = weekStartDate
        self.source = source
        self.rationale = rationale
        self.sessions = sessions
        self.weeklyVolumeTargets = weeklyVolumeTargets
    }
}
