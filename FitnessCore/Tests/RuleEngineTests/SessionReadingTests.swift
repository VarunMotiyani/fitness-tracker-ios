import Testing
import Foundation
import FitnessDomain
import Metrics
@testable import RuleEngine

struct SessionReadingTests {
    private func makeSet(reps: Int, loadKg: Double, isWarmup: Bool = false, done: Bool = true) -> LoggedSetSnapshot {
        let now = Date()
        return LoggedSetSnapshot(
            targetReps: 10,
            targetLoadKg: loadKg,
            actualReps: done ? reps : 0,
            actualLoadKg: loadKg,
            startedAt: now,
            completedAt: now.addingTimeInterval(30),
            restBeforeSec: 90,
            isWarmup: isWarmup
        )
    }

    @Test func allSetsDoneAtGoalIsOk() {
        let sets = [
            makeSet(reps: 10, loadKg: 80),
            makeSet(reps: 10, loadKg: 80),
            makeSet(reps: 10, loadKg: 80)
        ]
        let entry = CompletedEntrySnapshot(
            exerciseID: "bench",
            performedOrder: 0,
            state: .done,
            skipped: false,
            wasSwappedFrom: nil,
            feel: .right,
            note: nil,
            sets: sets
        )
        let target = PrescriptionTarget(sets: 3, reps: 10, loadKg: 80)
        let reading = SessionReadingReducer.read(entry: entry, target: target, fallbackTarget: target, date: Date())

        #expect(reading.ok == true)
        #expect(reading.count == 3)
        #expect(reading.low == 10)
        #expect(reading.amrap == 10)
        #expect(reading.weight == 80)
    }

    @Test func oneSetBelowGoalIsMiss() {
        let sets = [
            makeSet(reps: 10, loadKg: 80),
            makeSet(reps: 9, loadKg: 80),
            makeSet(reps: 10, loadKg: 80)
        ]
        let entry = CompletedEntrySnapshot(
            exerciseID: "bench",
            performedOrder: 0,
            state: .done,
            skipped: false,
            wasSwappedFrom: nil,
            feel: .brutal,
            note: nil,
            sets: sets
        )
        let target = PrescriptionTarget(sets: 3, reps: 10, loadKg: 80)
        let reading = SessionReadingReducer.read(entry: entry, target: target, fallbackTarget: target, date: Date())

        #expect(reading.ok == false)
        #expect(reading.low == 9)
    }

    @Test func fewerSetsThanPlannedIsMiss() {
        let sets = [
            makeSet(reps: 10, loadKg: 80),
            makeSet(reps: 10, loadKg: 80)
        ]
        let entry = CompletedEntrySnapshot(
            exerciseID: "bench",
            performedOrder: 0,
            state: .done,
            skipped: false,
            wasSwappedFrom: nil,
            feel: nil,
            note: nil,
            sets: sets
        )
        let target = PrescriptionTarget(sets: 3, reps: 10, loadKg: 80)
        let reading = SessionReadingReducer.read(entry: entry, target: target, fallbackTarget: target, date: Date())

        #expect(reading.ok == false)
    }

    @Test func warmupIgnoredInOkAndCount() {
        let sets = [
            makeSet(reps: 5, loadKg: 40, isWarmup: true, done: false),
            makeSet(reps: 10, loadKg: 80),
            makeSet(reps: 10, loadKg: 80),
            makeSet(reps: 10, loadKg: 80)
        ]
        let entry = CompletedEntrySnapshot(
            exerciseID: "bench",
            performedOrder: 0,
            state: .done,
            skipped: false,
            wasSwappedFrom: nil,
            feel: nil,
            note: nil,
            sets: sets
        )
        let target = PrescriptionTarget(sets: 3, reps: 10, loadKg: 80)
        let reading = SessionReadingReducer.read(entry: entry, target: target, fallbackTarget: target, date: Date())

        #expect(reading.ok == true)
        #expect(reading.count == 3)
        #expect(reading.low == 10)
    }

    @Test func timeModeReading() {
        let now = Date()
        let sets = [
            LoggedSetSnapshot(targetReps: 60, targetLoadKg: 0, actualReps: 0, actualLoadKg: 0, startedAt: now, completedAt: now.addingTimeInterval(60), restBeforeSec: 60, heldSec: 60),
            LoggedSetSnapshot(targetReps: 60, targetLoadKg: 0, actualReps: 0, actualLoadKg: 0, startedAt: now, completedAt: now.addingTimeInterval(65), restBeforeSec: 60, heldSec: 65)
        ]
        let entry = CompletedEntrySnapshot(exerciseID: "plank", performedOrder: 0, state: .done, skipped: false, wasSwappedFrom: nil, feel: nil, note: nil, sets: sets)
        let target = PrescriptionTarget(mode: .time, sets: 2, sec: 60)
        let reading = SessionReadingReducer.read(entry: entry, target: target, fallbackTarget: target, date: now)

        #expect(reading.ok == true)
        #expect(reading.mode == .time)
        #expect(reading.goal == 60)
        #expect(reading.heldPerSet == [60, 65])
    }

    @Test func historySkipsExcludedFromProgression() {
        let now = Date()
        let entry = CompletedEntrySnapshot(exerciseID: "bench", performedOrder: 0, state: .done, skipped: false, wasSwappedFrom: nil, feel: nil, note: nil, sets: [makeSet(reps: 10, loadKg: 80)])
        
        let s1 = CompletedSessionSnapshot(id: UUID(), date: now.addingTimeInterval(-86400 * 2), weekday: 1, timeOfDayMinutes: 600, plannedDurationMin: 60, actualDurationMin: 60, energy: .normal, timeAvailableMin: 60, outcome: .complete, partialReason: nil, coachSource: .rule, plannedSessionID: nil, entries: [entry], overallNote: nil, excludeFromProgression: false)
        let s2 = CompletedSessionSnapshot(id: UUID(), date: now.addingTimeInterval(-86400), weekday: 2, timeOfDayMinutes: 600, plannedDurationMin: 60, actualDurationMin: 60, energy: .normal, timeAvailableMin: 60, outcome: .complete, partialReason: nil, coachSource: .rule, plannedSessionID: nil, entries: [entry], overallNote: nil, excludeFromProgression: true)
        let s3 = CompletedSessionSnapshot(id: UUID(), date: now, weekday: 3, timeOfDayMinutes: 600, plannedDurationMin: 60, actualDurationMin: 60, energy: .normal, timeAvailableMin: 60, outcome: .complete, partialReason: nil, coachSource: .rule, plannedSessionID: nil, entries: [entry], overallNote: nil, excludeFromProgression: false)

        let target = PrescriptionTarget(sets: 1, reps: 10, loadKg: 80)
        let history = SessionReadingReducer.history(exerciseID: "bench", sessions: [s1, s2, s3], currentTarget: target)

        #expect(history.count == 2)
    }

    @Test func stallCountComputesConsecutiveMisses() {
        let now = Date()
        let okReading = SessionReading(mode: .reps, date: now, goal: 10, repsPerSet: [10], heldPerSet: [], weightKg: 80, count: 1, low: 10, amrap: 10, ok: true)
        let missReading = SessionReading(mode: .reps, date: now, goal: 10, repsPerSet: [8], heldPerSet: [], weightKg: 80, count: 1, low: 8, amrap: 8, ok: false)

        #expect(SessionReadingReducer.stallCount([okReading, missReading, missReading]) == 2)
        #expect(SessionReadingReducer.stallCount([missReading, okReading, missReading]) == 1)
        #expect(SessionReadingReducer.stallCount([okReading, okReading]) == 0)
        #expect(SessionReadingReducer.stallCount([missReading, missReading, missReading]) == 3)
    }
}
