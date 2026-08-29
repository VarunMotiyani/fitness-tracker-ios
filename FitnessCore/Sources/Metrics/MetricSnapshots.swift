import Foundation

public enum EnergyRating: String, CaseIterable, Sendable, Codable, Equatable {
    case beat
    case normal
    case great
}

public enum Feel: String, CaseIterable, Sendable, Codable, Equatable {
    case easy
    case right
    case brutal
}

public enum SessionOutcome: String, CaseIterable, Sendable, Codable, Equatable {
    case complete
    case partial
}

public enum PartialReason: String, CaseIterable, Sendable, Codable, Equatable {
    case ranOutOfTime
    case tooTired
    case painNiggle
    case gymCrowded
    case notFeelingIt
    case other
}

public enum EntryState: String, CaseIterable, Sendable, Codable, Equatable {
    case notStarted
    case inProgress
    case done
}

public enum CoachSource: String, CaseIterable, Sendable, Codable, Equatable {
    case ai
    case rule
}

public struct LoggedSetSnapshot: Sendable, Codable, Equatable {
    public let targetReps: Int
    public let targetLoadKg: Double?
    public let actualReps: Int
    public let actualLoadKg: Double
    public let startedAt: Date
    public let completedAt: Date
    public let restBeforeSec: Int
    public let rpe: Double?
    public let isWarmup: Bool
    public let isDropSet: Bool
    public let toFailure: Bool
    public let assisted: Bool

    public init(targetReps: Int, targetLoadKg: Double?, actualReps: Int, actualLoadKg: Double, startedAt: Date, completedAt: Date, restBeforeSec: Int, rpe: Double?, isWarmup: Bool, isDropSet: Bool, toFailure: Bool, assisted: Bool) {
        self.targetReps = targetReps
        self.targetLoadKg = targetLoadKg
        self.actualReps = actualReps
        self.actualLoadKg = actualLoadKg
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.restBeforeSec = restBeforeSec
        self.rpe = rpe
        self.isWarmup = isWarmup
        self.isDropSet = isDropSet
        self.toFailure = toFailure
        self.assisted = assisted
    }
}

public struct CompletedEntrySnapshot: Sendable, Codable, Equatable {
    public let exerciseID: String
    public let performedOrder: Int
    public let state: EntryState
    public let skipped: Bool
    public let wasSwappedFrom: String?
    public let feel: Feel?
    public let note: String?
    public let sets: [LoggedSetSnapshot]

    public init(exerciseID: String, performedOrder: Int, state: EntryState, skipped: Bool, wasSwappedFrom: String?, feel: Feel?, note: String?, sets: [LoggedSetSnapshot]) {
        self.exerciseID = exerciseID
        self.performedOrder = performedOrder
        self.state = state
        self.skipped = skipped
        self.wasSwappedFrom = wasSwappedFrom
        self.feel = feel
        self.note = note
        self.sets = sets
    }
}

public extension LoggedSetSnapshot {
    /// A set that genuinely contributes to metrics: not a warm-up, and actually performed.
    var isWorkingSet: Bool { !isWarmup && actualReps > 0 }
}

public extension CompletedEntrySnapshot {
    /// An exercise entry whose sets count toward metrics: performed, not skipped.
    var countsTowardMetrics: Bool { !skipped && state == .done }
}

public struct CompletedSessionSnapshot: Sendable, Codable, Equatable {
    public let id: UUID
    public let date: Date
    public let weekday: Int
    public let timeOfDayMinutes: Int
    public let plannedDurationMin: Int
    public let actualDurationMin: Int
    public let energy: EnergyRating
    public let timeAvailableMin: Int
    public let outcome: SessionOutcome
    public let partialReason: PartialReason?
    public let coachSource: CoachSource
    public let plannedSessionID: UUID?
    public let entries: [CompletedEntrySnapshot]
    public let overallNote: String?

    public init(id: UUID, date: Date, weekday: Int, timeOfDayMinutes: Int, plannedDurationMin: Int, actualDurationMin: Int, energy: EnergyRating, timeAvailableMin: Int, outcome: SessionOutcome, partialReason: PartialReason?, coachSource: CoachSource, plannedSessionID: UUID?, entries: [CompletedEntrySnapshot], overallNote: String?) {
        self.id = id
        self.date = date
        self.weekday = weekday
        self.timeOfDayMinutes = timeOfDayMinutes
        self.plannedDurationMin = plannedDurationMin
        self.actualDurationMin = actualDurationMin
        self.energy = energy
        self.timeAvailableMin = timeAvailableMin
        self.outcome = outcome
        self.partialReason = partialReason
        self.coachSource = coachSource
        self.plannedSessionID = plannedSessionID
        self.entries = entries
        self.overallNote = overallNote
    }
}

public struct BodyweightSnapshot: Sendable, Codable, Equatable {
    public let date: Date
    public let kg: Double

    public init(date: Date, kg: Double) {
        self.date = date
        self.kg = kg
    }
}

public struct DailyCheckinSnapshot: Sendable, Codable, Equatable {
    public let date: Date
    public let sleepQuality: Int?
    public let soreness: Int?
    public let note: String?

    public init(date: Date, sleepQuality: Int?, soreness: Int?, note: String?) {
        self.date = date
        self.sleepQuality = sleepQuality
        self.soreness = soreness
        self.note = note
    }
}

public struct ObservationSnapshot: Sendable, Codable, Equatable {
    public let kind: String
    public let value: Double
    public let unit: String
    public let timestamp: Date
    public let context: [String: String]
    public let sessionID: UUID?
    public let entryExerciseID: String?

    public init(kind: String, value: Double, unit: String, timestamp: Date, context: [String: String], sessionID: UUID?, entryExerciseID: String?) {
        self.kind = kind
        self.value = value
        self.unit = unit
        self.timestamp = timestamp
        self.context = context
        self.sessionID = sessionID
        self.entryExerciseID = entryExerciseID
    }
}
