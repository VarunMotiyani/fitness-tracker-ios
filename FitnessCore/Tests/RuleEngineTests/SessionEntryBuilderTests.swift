import Testing
import Foundation
import FitnessDomain
import Metrics
@testable import RuleEngine

struct SessionEntryBuilderTests {
    @Test func buildWithoutHistoryUsesBaselineTarget() {
        let target = PrescriptionTarget(sets: 3, reps: 10, loadKg: 80)
        let built = SessionEntryBuilder.build(
            exerciseID: "bench",
            target: target,
            mechanic: .compound,
            sessions: []
        )

        #expect(built.exerciseID == "bench")
        #expect(built.prescription.kind == .first)
        #expect(built.sets.count == 3)
        #expect(built.sets.first?.targetReps == 10)
        #expect(built.sets.first?.targetLoadKg == 80)
    }

    @Test func buildExcludedFromProgressionSetsKindOff() {
        let target = PrescriptionTarget(sets: 3, reps: 10, loadKg: 80)
        let built = SessionEntryBuilder.build(
            exerciseID: "bench",
            target: target,
            mechanic: .compound,
            sessions: [],
            excludeFromProgression: true
        )

        #expect(built.prescription.kind == .off)
        #expect(built.sets.count == 3)
    }

    @Test func buildWithSuccessHistoryIncreasesLoad() {
        let now = Date()
        let set = LoggedSetSnapshot(targetReps: 10, targetLoadKg: 100, actualReps: 10, actualLoadKg: 100, startedAt: now, completedAt: now, restBeforeSec: 90)
        let entry = CompletedEntrySnapshot(exerciseID: "bench", performedOrder: 0, state: .done, skipped: false, wasSwappedFrom: nil, feel: nil, note: nil, sets: [set, set, set])
        let session = CompletedSessionSnapshot(
            id: UUID(), date: now, weekday: 1, timeOfDayMinutes: 600, plannedDurationMin: 60, actualDurationMin: 60,
            energy: .normal, timeAvailableMin: 60, outcome: .complete, partialReason: nil, coachSource: .rule,
            plannedSessionID: nil, entries: [entry], overallNote: nil, excludeFromProgression: false
        )

        let target = PrescriptionTarget(sets: 3, reps: 10, loadKg: 100, incKg: 2.5, policy: .linear)
        let built = SessionEntryBuilder.build(
            exerciseID: "bench",
            target: target,
            mechanic: .compound,
            sessions: [session]
        )

        #expect(built.prescription.kind == .up)
        #expect(built.prescription.weightKg == 102.5)
        #expect(built.sets.first?.targetLoadKg == 102.5)
    }
}
