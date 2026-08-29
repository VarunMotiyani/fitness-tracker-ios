import Foundation
import SwiftData
import Metrics

/// A workout session that has been started (and possibly finished). `finishedAt == nil`
/// marks a session that is still in progress. Every enum-typed concept is stored as a
/// raw `String`/`Int` column. `coachSourceRaw` is always `"rule"` in Phase 2b.
@Model
final class CompletedSessionModel {
    var id: UUID
    var startedAt: Date
    var finishedAt: Date?
    var weekdayRaw: Int
    var timeOfDayMinutes: Int
    var plannedDurationMin: Int
    var actualDurationMin: Int
    var energyRaw: String
    var timeAvailableMin: Int
    var outcomeRaw: String?
    var partialReasonRaw: String?
    var coachSourceRaw: String
    var plannedSessionID: UUID?
    var overallNote: String?

    @Relationship(deleteRule: .cascade, inverse: \CompletedEntryModel.session)
    var entries: [CompletedEntryModel]

    init(id: UUID = UUID(), startedAt: Date, weekdayRaw: Int, timeOfDayMinutes: Int,
         plannedDurationMin: Int, energyRaw: String, timeAvailableMin: Int,
         plannedSessionID: UUID?) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = nil
        self.weekdayRaw = weekdayRaw
        self.timeOfDayMinutes = timeOfDayMinutes
        self.plannedDurationMin = plannedDurationMin
        self.actualDurationMin = 0
        self.energyRaw = energyRaw
        self.timeAvailableMin = timeAvailableMin
        self.outcomeRaw = nil
        self.partialReasonRaw = nil
        self.coachSourceRaw = "rule"
        self.plannedSessionID = plannedSessionID
        self.overallNote = nil
        self.entries = []
    }
}

/// One exercise performed within a session.
@Model
final class CompletedEntryModel {
    var exerciseID: String
    var performedOrder: Int
    var stateRaw: String
    var skipped: Bool
    var wasSwappedFrom: String?
    var feelRaw: String?
    var note: String?
    var session: CompletedSessionModel?

    @Relationship(deleteRule: .cascade, inverse: \LoggedSetModel.entry)
    var sets: [LoggedSetModel]

    init(exerciseID: String, performedOrder: Int) {
        self.exerciseID = exerciseID
        self.performedOrder = performedOrder
        self.stateRaw = EntryState.notStarted.rawValue
        self.skipped = false
        self.wasSwappedFrom = nil
        self.feelRaw = nil
        self.note = nil
        self.sets = []
    }
}

/// One logged set within an entry.
@Model
final class LoggedSetModel {
    var targetReps: Int
    var targetLoadKg: Double?
    var actualReps: Int
    var actualLoadKg: Double
    var startedAt: Date
    var completedAt: Date
    var restBeforeSec: Int
    var rpe: Double?
    var isWarmup: Bool
    var isDropSet: Bool
    var toFailure: Bool
    var assisted: Bool
    var entry: CompletedEntryModel?

    init(targetReps: Int, targetLoadKg: Double?, actualReps: Int, actualLoadKg: Double,
         startedAt: Date, completedAt: Date, restBeforeSec: Int) {
        self.targetReps = targetReps
        self.targetLoadKg = targetLoadKg
        self.actualReps = actualReps
        self.actualLoadKg = actualLoadKg
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.restBeforeSec = restBeforeSec
        self.rpe = nil
        self.isWarmup = false
        self.isDropSet = false
        self.toFailure = false
        self.assisted = false
    }
}
