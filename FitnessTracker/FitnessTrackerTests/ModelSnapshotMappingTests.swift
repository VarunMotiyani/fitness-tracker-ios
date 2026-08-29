import Testing
import Foundation
import Metrics
import CoachMemory
import FitnessDomain
@testable import FitnessTracker

@MainActor
@Suite struct ModelSnapshotMappingTests {

    // MARK: LoggedSetModel

    @Test func loggedSetMapsEveryField() {
        let started = Date(timeIntervalSince1970: 1_000)
        let completed = Date(timeIntervalSince1970: 1_060)
        let m = LoggedSetModel(targetReps: 8, targetLoadKg: 60, actualReps: 7,
                               actualLoadKg: 62.5, startedAt: started, completedAt: completed,
                               restBeforeSec: 90)
        m.rpe = 8.5
        m.isWarmup = true
        m.isDropSet = true
        m.toFailure = true
        m.assisted = true

        let s = m.toSnapshot()
        #expect(s.targetReps == 8)
        #expect(s.targetLoadKg == 60)
        #expect(s.actualReps == 7)
        #expect(s.actualLoadKg == 62.5)
        #expect(s.startedAt == started)
        #expect(s.completedAt == completed)
        #expect(s.restBeforeSec == 90)
        #expect(s.rpe == 8.5)
        #expect(s.isWarmup)
        #expect(s.isDropSet)
        #expect(s.toFailure)
        #expect(s.assisted)
    }

    @Test func loggedSetNilOptionals() {
        let m = LoggedSetModel(targetReps: 5, targetLoadKg: nil, actualReps: 5,
                               actualLoadKg: 40, startedAt: .init(), completedAt: .init(),
                               restBeforeSec: 0)
        let s = m.toSnapshot()
        #expect(s.targetLoadKg == nil)
        #expect(s.rpe == nil)
    }

    // MARK: CompletedEntryModel

    @Test func completedEntryMapsAndKeepsSetOrder() {
        let e = CompletedEntryModel(exerciseID: "Bench_Press", performedOrder: 2)
        e.stateRaw = EntryState.done.rawValue
        e.skipped = false
        e.wasSwappedFrom = "Incline_Press"
        e.feelRaw = Feel.brutal.rawValue
        e.note = "felt strong"
        let first = LoggedSetModel(targetReps: 1, targetLoadKg: nil, actualReps: 1, actualLoadKg: 1,
                                   startedAt: .init(), completedAt: .init(), restBeforeSec: 0)
        let second = LoggedSetModel(targetReps: 2, targetLoadKg: nil, actualReps: 2, actualLoadKg: 2,
                                    startedAt: .init(), completedAt: .init(), restBeforeSec: 0)
        e.sets = [first, second]

        let s = e.toSnapshot()
        #expect(s.exerciseID == "Bench_Press")
        #expect(s.performedOrder == 2)
        #expect(s.state == .done)
        #expect(s.skipped == false)
        #expect(s.wasSwappedFrom == "Incline_Press")
        #expect(s.feel == .brutal)
        #expect(s.note == "felt strong")
        #expect(s.sets.map(\.targetReps) == [1, 2])
    }

    @Test func completedEntryEnumFallbacks() {
        let e = CompletedEntryModel(exerciseID: "X", performedOrder: 0)
        e.stateRaw = "garbage"
        e.feelRaw = "garbage"
        let s = e.toSnapshot()
        #expect(s.state == .notStarted)
        #expect(s.feel == nil)
    }

    @Test func completedEntryNilFeelRaw() {
        let e = CompletedEntryModel(exerciseID: "X", performedOrder: 0)
        e.feelRaw = nil
        #expect(e.toSnapshot().feel == nil)
    }

    // MARK: CompletedSessionModel

    private func makeSession() -> CompletedSessionModel {
        CompletedSessionModel(id: UUID(), startedAt: Date(timeIntervalSince1970: 5_000),
                              weekdayRaw: 3, timeOfDayMinutes: 540, plannedDurationMin: 60,
                              energyRaw: EnergyRating.great.rawValue, timeAvailableMin: 75,
                              plannedSessionID: UUID())
    }

    @Test func completedSessionMapsEveryField() {
        let m = makeSession()
        m.finishedAt = Date(timeIntervalSince1970: 8_000)
        m.actualDurationMin = 55
        m.outcomeRaw = SessionOutcome.complete.rawValue
        m.partialReasonRaw = nil
        m.coachSourceRaw = CoachSource.ai.rawValue
        m.overallNote = "good"
        let e = CompletedEntryModel(exerciseID: "Squat", performedOrder: 0)
        m.entries = [e]

        let s = m.toSnapshot()
        #expect(s.id == m.id)
        #expect(s.date == m.startedAt)
        #expect(s.weekday == 3)
        #expect(s.timeOfDayMinutes == 540)
        #expect(s.plannedDurationMin == 60)
        #expect(s.actualDurationMin == 55)
        #expect(s.energy == .great)
        #expect(s.timeAvailableMin == 75)
        #expect(s.outcome == .complete)
        #expect(s.partialReason == nil)
        #expect(s.coachSource == .ai)
        #expect(s.plannedSessionID == m.plannedSessionID)
        #expect(s.entries.map(\.exerciseID) == ["Squat"])
        #expect(s.overallNote == "good")
    }

    @Test func completedSessionEnumFallbacks() {
        let m = makeSession()
        m.energyRaw = "garbage"
        m.outcomeRaw = nil            // unfinished -> .partial
        m.partialReasonRaw = "garbage"
        m.coachSourceRaw = "garbage"
        let s = m.toSnapshot()
        #expect(s.energy == .normal)
        #expect(s.outcome == .partial)
        #expect(s.partialReason == nil)
        #expect(s.coachSource == .rule)
    }

    @Test func completedSessionPartialReasonMaps() {
        let m = makeSession()
        m.outcomeRaw = SessionOutcome.partial.rawValue
        m.partialReasonRaw = PartialReason.ranOutOfTime.rawValue
        let s = m.toSnapshot()
        #expect(s.outcome == .partial)
        #expect(s.partialReason == .ranOutOfTime)
    }

    // MARK: Bodyweight / DailyCheckin

    @Test func bodyweightMaps() {
        let d = Date(timeIntervalSince1970: 123)
        let s = BodyweightEntryModel(date: d, kg: 74.2).toSnapshot()
        #expect(s.date == d)
        #expect(s.kg == 74.2)
    }

    @Test func dailyCheckinMaps() {
        let d = Date(timeIntervalSince1970: 123)
        let m = DailyCheckinModel(date: d)
        m.sleepQuality = 4
        m.soreness = 2
        m.note = "ok"
        let s = m.toSnapshot()
        #expect(s.date == d)
        #expect(s.sleepQuality == 4)
        #expect(s.soreness == 2)
        #expect(s.note == "ok")
    }

    @Test func dailyCheckinNilRatings() {
        let s = DailyCheckinModel(date: .init()).toSnapshot()
        #expect(s.sleepQuality == nil)
        #expect(s.soreness == nil)
        #expect(s.note == nil)
    }

    // MARK: ObservationModel

    @Test func observationMapsAndDecodesContext() {
        let ts = Date(timeIntervalSince1970: 42)
        let m = ObservationModel(kind: "e1rm", value: 100, unit: "kg", timestamp: ts)
        m.contextJSON = #"{"exercise":"Squat","week":"3"}"#
        m.sessionID = UUID()
        m.entryExerciseID = "Squat"
        let s = m.toSnapshot()
        #expect(s.kind == "e1rm")
        #expect(s.value == 100)
        #expect(s.unit == "kg")
        #expect(s.timestamp == ts)
        #expect(s.context == ["exercise": "Squat", "week": "3"])
        #expect(s.sessionID == m.sessionID)
        #expect(s.entryExerciseID == "Squat")
    }

    @Test func observationBadContextJSONFallsBackToEmpty() {
        let m = ObservationModel(kind: "k", value: 1, unit: "u", timestamp: .init())
        m.contextJSON = "not json"
        #expect(m.toSnapshot().context == [:])
    }

    // MARK: PersonalRecord round-trip

    @Test func personalRecordModelToSnapshot() {
        let d = Date(timeIntervalSince1970: 900)
        let sid = UUID()
        let m = PersonalRecordModel(typeRaw: PRType.estimated1RM.rawValue, exerciseID: "Deadlift",
                                    value: 180, atLoadKg: 170, reps: 3, date: d, sessionID: sid)
        let s = m.toSnapshot()
        #expect(s.type == .estimated1RM)
        #expect(s.exerciseID == "Deadlift")
        #expect(s.value == 180)
        #expect(s.atLoadKg == 170)
        #expect(s.reps == 3)
        #expect(s.date == d)
        #expect(s.sessionID == sid)
    }

    @Test func personalRecordTypeFallback() {
        let m = PersonalRecordModel(typeRaw: "garbage", exerciseID: "X", value: 1, atLoadKg: 1,
                                    reps: 1, date: .init(), sessionID: UUID())
        #expect(m.toSnapshot().type == .heaviestWeight)
    }

    @Test func personalRecordRoundTripLossless() {
        let original = PersonalRecord(type: .repsAtWeight, exerciseID: "OHP", value: 10,
                                      atLoadKg: 50, reps: 10, date: Date(timeIntervalSince1970: 111),
                                      sessionID: UUID())
        let back = personalRecordModel(from: original).toSnapshot()
        #expect(back == original)
    }

    // MARK: CoachMemory round-trip

    @Test func coachMemoryModelToDomain() {
        let id = UUID()
        let created = Date(timeIntervalSince1970: 100)
        let confirmed = Date(timeIntervalSince1970: 200)
        let m = CoachMemoryModel(id: id, kindRaw: MemoryKind.preference.rawValue,
                                 statement: "likes tempo work", confidence: 0.8,
                                 sourceKind: "agent", createdAt: created, lastConfirmedAt: confirmed)
        m.action = "add tempo cues"
        m.sourceAgent = "coach-v1"
        m.outcomeScore = 0.5
        m.retiredByCap = true
        m.tagExerciseID = "Squat"
        m.tagMuscleRaw = MuscleGroup.quads.rawValue
        m.tagEquipmentRaw = Equipment.barbell.rawValue
        m.tagFreeJSON = #"["a","b"]"#

        let d = m.toDomain()
        #expect(d.id == id)
        #expect(d.kind == .preference)
        #expect(d.statement == "likes tempo work")
        #expect(d.action == "add tempo cues")
        #expect(d.confidence == 0.8)
        #expect(d.source == .agent("coach-v1"))
        #expect(d.createdAt == created)
        #expect(d.lastConfirmedAt == confirmed)
        #expect(d.outcomeScore == 0.5)
        #expect(d.retiredByCap)
        #expect(d.tags.exerciseID == "Squat")
        #expect(d.tags.muscle == .quads)
        #expect(d.tags.equipment == .barbell)
        #expect(d.tags.freeTags == ["a", "b"])
    }

    @Test func coachMemoryUserSourceAndFallbacks() {
        let m = CoachMemoryModel(id: UUID(), kindRaw: "garbage", statement: "s", confidence: 0.5,
                                 sourceKind: "user", createdAt: .init(), lastConfirmedAt: .init())
        m.tagMuscleRaw = "garbage"
        m.tagEquipmentRaw = "garbage"
        m.tagFreeJSON = "not json"
        let d = m.toDomain()
        #expect(d.kind == .observation)
        #expect(d.source == .user)
        #expect(d.tags.muscle == nil)
        #expect(d.tags.equipment == nil)
        #expect(d.tags.freeTags == [])
    }

    @Test func coachMemoryAgentSourceMissingAgentName() {
        let m = CoachMemoryModel(id: UUID(), kindRaw: MemoryKind.goal.rawValue, statement: "s",
                                 confidence: 0.5, sourceKind: "agent", createdAt: .init(),
                                 lastConfirmedAt: .init())
        m.sourceAgent = nil
        #expect(m.toDomain().source == .agent("unknown"))
    }

    @Test func coachMemoryDanglingSupersededByIsRetired() {
        let m = CoachMemoryModel(id: UUID(), kindRaw: MemoryKind.observation.rawValue, statement: "s",
                                 confidence: 0.5, sourceKind: "user", createdAt: .init(),
                                 lastConfirmedAt: .init())
        m.supersededBy = UUID()   // no matching row
        let d = m.toDomain()
        #expect(d.supersededBy == m.supersededBy)
        #expect(d.isRetired == true)
    }

    @Test func coachMemoryRoundTripLossless() {
        let original = CoachMemory(
            id: UUID(), kind: .responsePattern, statement: "responds well to short rests",
            action: nil, confidence: 0.65, source: .agent("planner"),
            createdAt: Date(timeIntervalSince1970: 10), lastConfirmedAt: Date(timeIntervalSince1970: 20),
            supersededBy: UUID(),
            tags: MemoryTags(exerciseID: "Row", muscle: .back, equipment: .cable, freeTags: ["x"]),
            outcomeScore: -0.25, retiredByCap: true)
        let back = coachMemoryModel(from: original).toDomain()
        #expect(back == original)
    }

    @Test func coachMemoryRoundTripUserSource() {
        let original = CoachMemory(
            id: UUID(), kind: .constraint, statement: "no overhead pressing",
            action: "swap to landmine", confidence: 1.0, source: .user,
            createdAt: Date(timeIntervalSince1970: 1), lastConfirmedAt: Date(timeIntervalSince1970: 2),
            supersededBy: nil, tags: MemoryTags(), outcomeScore: nil, retiredByCap: false)
        let back = coachMemoryModel(from: original).toDomain()
        #expect(back == original)
    }
}
