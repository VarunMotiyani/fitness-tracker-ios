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

public struct DropSetEntry: Sendable, Codable, Equatable {
    public let loadKg: Double
    public let reps: Int

    public init(loadKg: Double, reps: Int) {
        self.loadKg = loadKg
        self.reps = reps
    }
}

public struct RestPauseCluster: Sendable, Codable, Equatable {
    public let reps: Int
    public let restSeconds: Int

    public init(reps: Int, restSeconds: Int = 15) {
        self.reps = reps
        self.restSeconds = restSeconds
    }
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
    public let drops: [DropSetEntry]
    public let clusters: [RestPauseCluster]
    public let heldSec: Int?
    public let rir: Double?

    public init(
        targetReps: Int,
        targetLoadKg: Double?,
        actualReps: Int,
        actualLoadKg: Double,
        startedAt: Date,
        completedAt: Date,
        restBeforeSec: Int,
        rpe: Double? = nil,
        isWarmup: Bool = false,
        isDropSet: Bool = false,
        toFailure: Bool = false,
        assisted: Bool = false,
        drops: [DropSetEntry] = [],
        clusters: [RestPauseCluster] = [],
        heldSec: Int? = nil,
        rir: Double? = nil
    ) {
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
        self.drops = drops
        self.clusters = clusters
        self.heldSec = heldSec
        self.rir = rir
    }

    /// Normalized reps-in-reserve: returns `rir` if set, or converts `rpe` (10 - rpe)
    public var effortRIR: Double? {
        if let rir = rir { return rir }
        if let rpe = rpe { return 10.0 - rpe }
        return nil
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
    public let notePin: Bool
    public let sets: [LoggedSetSnapshot]

    public init(
        exerciseID: String,
        performedOrder: Int,
        state: EntryState,
        skipped: Bool,
        wasSwappedFrom: String?,
        feel: Feel?,
        note: String?,
        notePin: Bool = false,
        sets: [LoggedSetSnapshot]
    ) {
        self.exerciseID = exerciseID
        self.performedOrder = performedOrder
        self.state = state
        self.skipped = skipped
        self.wasSwappedFrom = wasSwappedFrom
        self.feel = feel
        self.note = note
        self.notePin = notePin
        self.sets = sets
    }

    private enum CodingKeys: String, CodingKey {
        case exerciseID, performedOrder, state, skipped, wasSwappedFrom, feel, note, notePin, sets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.exerciseID = try container.decode(String.self, forKey: .exerciseID)
        self.performedOrder = try container.decode(Int.self, forKey: .performedOrder)
        self.state = try container.decode(EntryState.self, forKey: .state)
        self.skipped = try container.decode(Bool.self, forKey: .skipped)
        self.wasSwappedFrom = try container.decodeIfPresent(String.self, forKey: .wasSwappedFrom)
        self.feel = try container.decodeIfPresent(Feel.self, forKey: .feel)
        self.note = try container.decodeIfPresent(String.self, forKey: .note)
        self.notePin = try container.decodeIfPresent(Bool.self, forKey: .notePin) ?? false
        self.sets = try container.decode([LoggedSetSnapshot].self, forKey: .sets)
    }
}

public extension LoggedSetSnapshot {
    /// A set that genuinely contributes to metrics: not a warm-up, and actually performed.
    var isWorkingSet: Bool { !isWarmup && actualReps > 0 }
    
    /// Total intensity-weighted volume of drops on top of the main set.
    var extraDropVolumeKg: Double {
        drops.reduce(0.0) { $0 + ($1.loadKg * Double($1.reps)) }
    }
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
    public let excludeFromProgression: Bool

    public init(
        id: UUID,
        date: Date,
        weekday: Int,
        timeOfDayMinutes: Int,
        plannedDurationMin: Int,
        actualDurationMin: Int,
        energy: EnergyRating,
        timeAvailableMin: Int,
        outcome: SessionOutcome,
        partialReason: PartialReason?,
        coachSource: CoachSource,
        plannedSessionID: UUID?,
        entries: [CompletedEntrySnapshot],
        overallNote: String?,
        excludeFromProgression: Bool = false
    ) {
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
        self.excludeFromProgression = excludeFromProgression
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, weekday, timeOfDayMinutes, plannedDurationMin, actualDurationMin, energy, timeAvailableMin, outcome, partialReason, coachSource, plannedSessionID, entries, overallNote, excludeFromProgression
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
