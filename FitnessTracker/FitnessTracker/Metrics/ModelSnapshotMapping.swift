import Foundation
import SwiftData
import Metrics
import CoachMemory
import FitnessDomain

/// The one on-disk value that maps to `MemorySource.user`; anything else is an
/// agent memory. Named so the 2c memory-keeper can't typo it into a silent
/// `.agent`.
private nonisolated let userSourceKind = "user"

// MARK: - JSON helpers

private nonisolated func decodeStringMap(_ json: String) -> [String: String] {
    guard let data = json.data(using: .utf8),
          let map = try? JSONDecoder().decode([String: String].self, from: data)
    else { return [:] }
    return map
}

private nonisolated func decodeStringArray(_ json: String) -> [String] {
    guard let data = json.data(using: .utf8),
          let arr = try? JSONDecoder().decode([String].self, from: data)
    else { return [] }
    return arr
}

private nonisolated func encodeStringArray(_ arr: [String]) -> String {
    guard let data = try? JSONEncoder().encode(arr),
          let str = String(data: data, encoding: .utf8)
    else { return "[]" }
    return str
}

private nonisolated func decodeDrops(_ json: String) -> [DropSetEntry] {
    guard let data = json.data(using: .utf8),
          let drops = try? JSONDecoder().decode([DropSetEntry].self, from: data)
    else { return [] }
    return drops
}

public nonisolated func encodeDrops(_ drops: [DropSetEntry]) -> String {
    guard let data = try? JSONEncoder().encode(drops),
          let str = String(data: data, encoding: .utf8)
    else { return "[]" }
    return str
}

private nonisolated func decodeClusters(_ json: String) -> [RestPauseCluster] {
    guard let data = json.data(using: .utf8),
          let clusters = try? JSONDecoder().decode([RestPauseCluster].self, from: data)
    else { return [] }
    return clusters
}

public nonisolated func encodeClusters(_ clusters: [RestPauseCluster]) -> String {
    guard let data = try? JSONEncoder().encode(clusters),
          let str = String(data: data, encoding: .utf8)
    else { return "[]" }
    return str
}

// MARK: - Session models -> snapshots

extension LoggedSetModel {
    func toSnapshot() -> LoggedSetSnapshot {
        LoggedSetSnapshot(
            targetReps: targetReps,
            targetLoadKg: targetLoadKg,
            actualReps: actualReps,
            actualLoadKg: actualLoadKg,
            startedAt: startedAt,
            completedAt: completedAt,
            restBeforeSec: restBeforeSec,
            rpe: rpe,
            isWarmup: isWarmup,
            isDropSet: isDropSet,
            toFailure: toFailure,
            assisted: assisted,
            drops: decodeDrops(dropsJSON),
            clusters: decodeClusters(clustersJSON),
            heldSec: heldSec,
            rir: rir
        )
    }
}

extension CompletedEntryModel {
    func toSnapshot() -> CompletedEntrySnapshot {
        CompletedEntrySnapshot(
            exerciseID: exerciseID,
            performedOrder: performedOrder,
            state: EntryState(rawValue: stateRaw) ?? .notStarted,
            skipped: skipped,
            wasSwappedFrom: wasSwappedFrom,
            feel: feelRaw.flatMap(Feel.init(rawValue:)),
            note: note,
            sets: sets.sorted { $0.startedAt < $1.startedAt }.map { $0.toSnapshot() }   // R5 / F6
        )
    }
}

extension CompletedSessionModel {
    func toSnapshot() -> CompletedSessionSnapshot {
        CompletedSessionSnapshot(
            id: id,
            date: startedAt,
            weekday: weekdayRaw,
            timeOfDayMinutes: timeOfDayMinutes,
            plannedDurationMin: plannedDurationMin,
            actualDurationMin: actualDurationMin,
            energy: EnergyRating(rawValue: energyRaw) ?? .normal,
            timeAvailableMin: timeAvailableMin,
            outcome: outcomeRaw.flatMap(SessionOutcome.init(rawValue:)) ?? .partial,
            partialReason: partialReasonRaw.flatMap(PartialReason.init(rawValue:)),
            coachSource: CoachSource(rawValue: coachSourceRaw) ?? .rule,
            plannedSessionID: plannedSessionID,
            entries: entries.sorted { $0.performedOrder < $1.performedOrder }.map { $0.toSnapshot() },   // R5 / F6
            overallNote: overallNote
        )
    }
}

// MARK: - Health models -> snapshots

extension BodyweightEntryModel {
    func toSnapshot() -> BodyweightSnapshot {
        BodyweightSnapshot(date: date, kg: kg)
    }
}

extension DailyCheckinModel {
    func toSnapshot() -> DailyCheckinSnapshot {
        DailyCheckinSnapshot(date: date, sleepQuality: sleepQuality, soreness: soreness, note: note)
    }
}

extension ObservationModel {
    func toSnapshot() -> ObservationSnapshot {
        ObservationSnapshot(
            kind: kind,
            value: value,
            unit: unit,
            timestamp: timestamp,
            context: decodeStringMap(contextJSON),
            sessionID: sessionID,
            entryExerciseID: entryExerciseID
        )
    }
}

// MARK: - PersonalRecord

extension PersonalRecordModel {
    func toSnapshot() -> PersonalRecord {
        PersonalRecord(
            type: PRType(rawValue: typeRaw) ?? .heaviestWeight,
            exerciseID: exerciseID,
            value: value,
            atLoadKg: atLoadKg,
            reps: reps,
            date: date,
            sessionID: sessionID
        )
    }
}

func personalRecordModel(from pr: PersonalRecord) -> PersonalRecordModel {
    PersonalRecordModel(
        typeRaw: pr.type.rawValue,
        exerciseID: pr.exerciseID,
        value: pr.value,
        atLoadKg: pr.atLoadKg,
        reps: pr.reps,
        date: pr.date,
        sessionID: pr.sessionID
    )
}

// MARK: - CoachMemory

extension CoachMemoryModel {
    func toDomain() -> CoachMemory {
        let source: MemorySource = sourceKind == userSourceKind ? .user : .agent(sourceAgent ?? "unknown")
        let tags = MemoryTags(
            exerciseID: tagExerciseID,
            muscle: tagMuscleRaw.flatMap(MuscleGroup.init(rawValue:)),
            equipment: tagEquipmentRaw.flatMap(Equipment.init(rawValue:)),
            freeTags: decodeStringArray(tagFreeJSON)
        )
        return CoachMemory(
            id: id,
            kind: MemoryKind(rawValue: kindRaw) ?? .observation,
            statement: statement,
            action: action,
            confidence: confidence,
            source: source,
            createdAt: createdAt,
            lastConfirmedAt: lastConfirmedAt,
            supersededBy: supersededBy,
            tags: tags,
            outcomeScore: outcomeScore,
            retiredByCap: retiredByCap
        )
    }
}

func coachMemoryModel(from m: CoachMemory) -> CoachMemoryModel {
    let sourceKind: String
    let sourceAgent: String?
    switch m.source {
    case .user:
        sourceKind = userSourceKind
        sourceAgent = nil
    case .agent(let name):
        sourceKind = "agent"
        sourceAgent = name
    }

    let model = CoachMemoryModel(
        id: m.id,
        kindRaw: m.kind.rawValue,
        statement: m.statement,
        confidence: m.confidence,
        sourceKind: sourceKind,
        createdAt: m.createdAt,
        lastConfirmedAt: m.lastConfirmedAt
    )
    model.action = m.action
    model.sourceAgent = sourceAgent
    model.supersededBy = m.supersededBy
    model.retiredByCap = m.retiredByCap
    model.outcomeScore = m.outcomeScore
    model.tagExerciseID = m.tags.exerciseID
    model.tagMuscleRaw = m.tags.muscle?.rawValue
    model.tagEquipmentRaw = m.tags.equipment?.rawValue
    model.tagFreeJSON = encodeStringArray(m.tags.freeTags)
    return model
}
