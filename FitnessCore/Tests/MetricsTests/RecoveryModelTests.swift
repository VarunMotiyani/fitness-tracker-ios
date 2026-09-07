import Testing
import Foundation
import FitnessDomain
import ExerciseCatalog
@testable import Metrics

@Suite struct RecoveryModelTests {
    private func makeCatalog() -> CatalogStore {
        let bench = Exercise(
            id: "bench_press",
            name: "Barbell Bench Press",
            primaryMuscle: .chest,
            secondaryMuscles: [.triceps, .shoulders],
            equipment: .barbell,
            mechanic: .compound,
            force: .push,
            difficulty: .intermediate,
            isUnilateral: false,
            instructions: [],
            imagePaths: []
        )
        let squat = Exercise(
            id: "barbell_squat",
            name: "Barbell Squat",
            primaryMuscle: .quads,
            secondaryMuscles: [.glutes, .lowerBack],
            equipment: .barbell,
            mechanic: .compound,
            force: .push,
            difficulty: .intermediate,
            isUnilateral: false,
            instructions: [],
            imagePaths: []
        )
        return CatalogStore(exercises: [bench, squat])
    }

    @Test func freshUntrainedProfileIsReadyWithBaselineStrength() {
        let catalog = makeCatalog()
        let recovery = RecoveryModel.computeRecovery(from: [], catalog: catalog, now: .now)

        for muscle in MuscleGroup.allCases {
            let status = recovery[muscle]!
            #expect(status.state == .ready)
            #expect(status.fatigueScore == 0)
            #expect(status.retainedStrengthScore == 0.5)
            #expect(status.lastTrainedDate == nil)
        }
    }

    @Test func recentHardSessionMakesMuscleFatiguedThenDecays() {
        let catalog = makeCatalog()
        let baseDate = Date(timeIntervalSince1970: 1_000_000)

        let set1 = LoggedSetSnapshot(targetReps: 8, targetLoadKg: 100, actualReps: 8, actualLoadKg: 100, startedAt: baseDate, completedAt: baseDate, restBeforeSec: 120, rpe: nil, isWarmup: false, isDropSet: false, toFailure: false, assisted: false)
        let set2 = LoggedSetSnapshot(targetReps: 8, targetLoadKg: 100, actualReps: 8, actualLoadKg: 100, startedAt: baseDate, completedAt: baseDate, restBeforeSec: 120, rpe: nil, isWarmup: false, isDropSet: false, toFailure: false, assisted: false)
        let set3 = LoggedSetSnapshot(targetReps: 8, targetLoadKg: 100, actualReps: 8, actualLoadKg: 100, startedAt: baseDate, completedAt: baseDate, restBeforeSec: 120, rpe: nil, isWarmup: false, isDropSet: false, toFailure: false, assisted: false)

        let entry = CompletedEntrySnapshot(exerciseID: "bench_press", performedOrder: 0, state: .done, skipped: false, wasSwappedFrom: nil, feel: .right, note: nil, sets: [set1, set2, set3])
        let session = CompletedSessionSnapshot(id: UUID(), date: baseDate, weekday: 2, timeOfDayMinutes: 600, plannedDurationMin: 60, actualDurationMin: 60, energy: .normal, timeAvailableMin: 60, outcome: .complete, partialReason: nil, coachSource: .rule, plannedSessionID: nil, entries: [entry], overallNote: nil)

        // Immediately after session (0 elapsed time)
        let recoveryNow = RecoveryModel.computeRecovery(from: [session], catalog: catalog, now: baseDate)
        let chestNow = recoveryNow[.chest]!
        #expect(chestNow.state == .fatigued)
        #expect(chestNow.fatigueScore > 0.5)
        #expect(chestNow.retainedStrengthScore == 1.0)
        #expect(chestNow.lastTrainedDate == baseDate)

        // 36 hours later (1 half-life) -> fatigue should decay significantly
        let after36h = baseDate.addingTimeInterval(36 * 3600)
        let recovery36h = RecoveryModel.computeRecovery(from: [session], catalog: catalog, now: after36h)
        let chest36h = recovery36h[.chest]!
        #expect(chest36h.fatigueScore < chestNow.fatigueScore)
        #expect(chest36h.state == .recovering || chest36h.state == .ready)

        // 5 days later -> fatigue should be near zero (ready), strength still 1.0
        let after5d = baseDate.addingTimeInterval(5 * 24 * 3600)
        let recovery5d = RecoveryModel.computeRecovery(from: [session], catalog: catalog, now: after5d)
        let chest5d = recovery5d[.chest]!
        #expect(chest5d.state == .ready)
        #expect(chest5d.fatigueScore < 0.15)
        #expect(chest5d.retainedStrengthScore == 1.0)
    }
}
