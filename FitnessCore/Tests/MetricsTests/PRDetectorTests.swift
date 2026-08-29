import Testing
import Foundation
@testable import Metrics

@Suite struct PRDetectorTests {
    private func session(_ exID: String, _ sets: [(reps: Int, load: Double)], id: UUID = UUID()) -> CompletedSessionSnapshot {
        let logged = sets.map { s in
            LoggedSetSnapshot(targetReps: s.reps, targetLoadKg: s.load, actualReps: s.reps,
                actualLoadKg: s.load, startedAt: .init(timeIntervalSince1970: 0),
                completedAt: .init(timeIntervalSince1970: 30), restBeforeSec: 90, rpe: nil,
                isWarmup: false, isDropSet: false, toFailure: false, assisted: false)
        }
        let entry = CompletedEntrySnapshot(exerciseID: exID, performedOrder: 0, state: .done,
            skipped: false, wasSwappedFrom: nil, feel: .right, note: nil, sets: logged)
        return CompletedSessionSnapshot(id: id, date: .init(timeIntervalSince1970: 1000), weekday: 3,
            timeOfDayMinutes: 600, plannedDurationMin: 60, actualDurationMin: 60, energy: .normal,
            timeAvailableMin: 60, outcome: .complete, partialReason: nil, coachSource: .rule,
            plannedSessionID: nil, entries: [entry], overallNote: nil)
    }

    @Test func firstEverSessionSeedsRecords() {
        let prs = PRDetector.newPRs(in: session("squat", [(5, 100)]), priorPRs: [])
        #expect(prs.contains { $0.type == .heaviestWeight && $0.value == 100 })
        #expect(prs.contains { $0.type == .estimated1RM })
    }
    @Test func heavierWeightIsAPR() {
        let prior = [PersonalRecord(type: .heaviestWeight, exerciseID: "squat", value: 100,
            atLoadKg: 100, reps: 5, date: .init(timeIntervalSince1970: 0), sessionID: UUID())]
        let prs = PRDetector.newPRs(in: session("squat", [(3, 105)]), priorPRs: prior)
        #expect(prs.contains { $0.type == .heaviestWeight && $0.value == 105 })
    }
    @Test func equalWeightIsNotAPR() {
        let prior = [PersonalRecord(type: .heaviestWeight, exerciseID: "squat", value: 100,
            atLoadKg: 100, reps: 5, date: .init(timeIntervalSince1970: 0), sessionID: UUID())]
        let prs = PRDetector.newPRs(in: session("squat", [(5, 100)]), priorPRs: prior)
        #expect(!prs.contains { $0.type == .heaviestWeight })
    }
    @Test func warmupSetsAreIgnored() {
        var s = session("bench", [(1, 140)])
        // mark the single set a warmup
        let warm = LoggedSetSnapshot(targetReps: 1, targetLoadKg: 140, actualReps: 1, actualLoadKg: 140,
            startedAt: .init(timeIntervalSince1970: 0), completedAt: .init(timeIntervalSince1970: 5),
            restBeforeSec: 0, rpe: nil, isWarmup: true, isDropSet: false, toFailure: false, assisted: false)
        s = CompletedSessionSnapshot(id: s.id, date: s.date, weekday: s.weekday,
            timeOfDayMinutes: s.timeOfDayMinutes, plannedDurationMin: s.plannedDurationMin,
            actualDurationMin: s.actualDurationMin, energy: s.energy, timeAvailableMin: s.timeAvailableMin,
            outcome: s.outcome, partialReason: nil, coachSource: .rule, plannedSessionID: nil,
            entries: [CompletedEntrySnapshot(exerciseID: "bench", performedOrder: 0, state: .done,
                skipped: false, wasSwappedFrom: nil, feel: .right, note: nil, sets: [warm])],
            overallNote: nil)
        #expect(PRDetector.newPRs(in: s, priorPRs: []).isEmpty)
    }
    @Test func skippedZeroRepEntryProducesNoPR() {
        // A skipped entry persisted with actualReps: 0 at the target load must not
        // seed a heaviestWeight / estimated1RM / repsAtWeight record.
        let ghost = LoggedSetSnapshot(targetReps: 5, targetLoadKg: 120, actualReps: 0, actualLoadKg: 120,
            startedAt: .init(timeIntervalSince1970: 0), completedAt: .init(timeIntervalSince1970: 0),
            restBeforeSec: 0, rpe: nil, isWarmup: false, isDropSet: false, toFailure: false, assisted: false)
        let entry = CompletedEntrySnapshot(exerciseID: "bench", performedOrder: 0, state: .done,
            skipped: true, wasSwappedFrom: nil, feel: nil, note: nil, sets: [ghost])
        let s = CompletedSessionSnapshot(id: UUID(), date: .init(timeIntervalSince1970: 1000), weekday: 3,
            timeOfDayMinutes: 600, plannedDurationMin: 60, actualDurationMin: 60, energy: .normal,
            timeAvailableMin: 60, outcome: .complete, partialReason: nil, coachSource: .rule,
            plannedSessionID: nil, entries: [entry], overallNote: nil)
        #expect(PRDetector.newPRs(in: s, priorPRs: []).isEmpty)
    }

    @Test func perExerciseIsolation() {
        let prior = [PersonalRecord(type: .heaviestWeight, exerciseID: "squat", value: 200,
            atLoadKg: 200, reps: 1, date: .init(timeIntervalSince1970: 0), sessionID: UUID())]
        let prs = PRDetector.newPRs(in: session("bench", [(5, 80)]), priorPRs: prior)
        #expect(prs.contains { $0.type == .heaviestWeight && $0.exerciseID == "bench" && $0.value == 80 })
    }
}
