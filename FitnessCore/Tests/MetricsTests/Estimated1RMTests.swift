import Testing
import Foundation
import FitnessDomain
@testable import Metrics

@Suite struct Estimated1RMTests {
    @Test func epleyKnownValues() {
        #expect(Estimated1RM.epley(loadKg: 100, reps: 1) == 100)          // 1-rep clamps to load
        #expect(abs(Estimated1RM.epley(loadKg: 100, reps: 10) - 133.3) < 0.1)
        #expect(abs(Estimated1RM.epley(loadKg: 60, reps: 5) - 70) < 0.1)
    }

    @Test func allThreeFormulasAtOneRepEqualLoad() {
        #expect(Estimated1RM.estimate(loadKg: 100, reps: 1, formula: .epley) == 100)
        #expect(Estimated1RM.estimate(loadKg: 100, reps: 1, formula: .brzycki) == 100)
        #expect(Estimated1RM.estimate(loadKg: 100, reps: 1, formula: .lombardi) == 100)
    }

    @Test func brzyckiAndLombardiKnownEstimates() {
        // Brzycki: 100 * 36 / (37 - 5) = 100 * 36 / 32 = 112.5
        let brz = Estimated1RM.estimate(loadKg: 100, reps: 5, formula: .brzycki)
        #expect(brz == 112.5)

        // Lombardi: 100 * (10 ^ 0.1) = 100 * 1.2589... = 125.9
        let lom = Estimated1RM.estimate(loadKg: 100, reps: 10, formula: .lombardi)
        #expect(lom == 125.9)
    }

    @Test func estimateClampsAboveRepCap() {
        #expect(Estimated1RM.estimate(loadKg: 100, reps: 13, formula: .epley) == nil)
        #expect(Estimated1RM.estimate(loadKg: 100, reps: 12, formula: .epley) != nil)
    }

    @Test func nonPositiveValuesReturnNil() {
        #expect(Estimated1RM.estimate(loadKg: 0, reps: 5) == nil)
        #expect(Estimated1RM.estimate(loadKg: -10, reps: 5) == nil)
        #expect(Estimated1RM.estimate(loadKg: 100, reps: 0) == nil)
        #expect(Estimated1RM.estimate(loadKg: 100, reps: -1) == nil)
    }

    @Test func bestSetFindsHighestEstimate() {
        let now = Date()
        let sets = [
            LoggedSetSnapshot(targetReps: 10, targetLoadKg: 80, actualReps: 10, actualLoadKg: 80, startedAt: now, completedAt: now, restBeforeSec: 60), // e1RM = 106.7
            LoggedSetSnapshot(targetReps: 5, targetLoadKg: 100, actualReps: 5, actualLoadKg: 100, startedAt: now, completedAt: now, restBeforeSec: 60),  // e1RM = 116.7
            LoggedSetSnapshot(targetReps: 1, targetLoadKg: 110, actualReps: 1, actualLoadKg: 110, startedAt: now, completedAt: now, restBeforeSec: 60)   // e1RM = 110.0
        ]
        let entry = CompletedEntrySnapshot(exerciseID: "bench", performedOrder: 0, state: .done, skipped: false, wasSwappedFrom: nil, feel: nil, note: nil, sets: sets)
        let best = Estimated1RM.bestSet(in: entry, formula: .epley)

        #expect(best != nil)
        #expect(best?.loadKg == 100)
        #expect(best?.reps == 5)
        #expect(best?.est == 116.7)
    }

    @Test func isRecordDetectsNewRecord() {
        let now = Date()
        let s1 = CompletedSessionSnapshot(
            id: UUID(), date: now.addingTimeInterval(-86400 * 7), weekday: 1, timeOfDayMinutes: 600,
            plannedDurationMin: 60, actualDurationMin: 60, energy: .normal, timeAvailableMin: 60,
            outcome: .complete, partialReason: nil, coachSource: .rule, plannedSessionID: nil,
            entries: [
                CompletedEntrySnapshot(
                    exerciseID: "bench", performedOrder: 0, state: .done, skipped: false, wasSwappedFrom: nil, feel: nil, note: nil,
                    sets: [LoggedSetSnapshot(targetReps: 5, targetLoadKg: 100, actualReps: 5, actualLoadKg: 100, startedAt: now, completedAt: now, restBeforeSec: 60)] // e1RM = 116.7
                )
            ], overallNote: nil, excludeFromProgression: false
        )

        let newEntry = CompletedEntrySnapshot(
            exerciseID: "bench", performedOrder: 0, state: .done, skipped: false, wasSwappedFrom: nil, feel: nil, note: nil,
            sets: [LoggedSetSnapshot(targetReps: 5, targetLoadKg: 105, actualReps: 5, actualLoadKg: 105, startedAt: now, completedAt: now, restBeforeSec: 60)] // e1RM = 122.5
        )

        let record = Estimated1RM.isRecord(exerciseID: "bench", entry: newEntry, priorSessions: [s1], formula: .epley)
        #expect(record != nil)
        #expect(record?.previous == 116.7)
        #expect(record?.est == 122.5)
    }

    @Test func prTypeHasThreeCases() { #expect(PRType.allCases.count == 3) }
}
