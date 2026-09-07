import Testing
import Foundation
import FitnessDomain
import ExerciseCatalog
import Metrics
@testable import FitnessTracker

/// `SessionFinalizer` runs the deterministic rule-engine finalisation:
/// per-exercise progression, then an energy trim, then a time trim. This is the
/// seam Phase 2c later swaps the AI `finalize` call into.
@MainActor
@Suite struct SessionFinalizerTests {

    // MARK: - Fixtures

    private static let cal: Calendar = .isoUTC

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        return Self.cal.date(from: c)!
    }

    private func exercise(_ id: String, _ mechanic: Mechanic, _ primary: MuscleGroup) -> Exercise {
        Exercise(id: id, name: id, primaryMuscle: primary, secondaryMuscles: [],
                 equipment: .barbell, mechanic: mechanic, force: .push,
                 difficulty: .intermediate, isUnilateral: false, instructions: [], imagePaths: [])
    }

    private func catalog() -> CatalogStore {
        CatalogStore(exercises: [
            exercise("bench", .compound, .chest),
            exercise("fly", .isolation, .chest),
        ])
    }

    /// One finished session: `bench` at 3 sets of 8 reps @ 60 kg, feel `.easy`,
    /// every working set at the top of the rep range — so `ProgressionRule` bumps
    /// the load on the next session.
    private func repository() -> InMemoryMetricsRepository {
        let sessionDate = date(2026, 8, 20)
        let set = LoggedSetSnapshot(
            targetReps: 8, targetLoadKg: 60, actualReps: 8, actualLoadKg: 60,
            startedAt: sessionDate, completedAt: sessionDate, restBeforeSec: 90,
            rpe: nil, isWarmup: false, isDropSet: false, toFailure: false, assisted: false
        )
        let entry = CompletedEntrySnapshot(
            exerciseID: "bench", performedOrder: 0, state: .done, skipped: false,
            wasSwappedFrom: nil, feel: .easy, note: nil, sets: [set, set, set]
        )
        let session = CompletedSessionSnapshot(
            id: UUID(), date: sessionDate, weekday: 4, timeOfDayMinutes: 720,
            plannedDurationMin: 60, actualDurationMin: 60, energy: .normal,
            timeAvailableMin: 90, outcome: .complete, partialReason: nil,
            coachSource: .rule, plannedSessionID: nil, entries: [entry], overallNote: nil
        )
        return InMemoryMetricsRepository(
            sessions: [session], priorPRs: [], observations: [],
            plannedSessionsPerWeek: 3, catalog: catalog()
        )
    }

    private func benchItem() -> PlannedItem {
        PlannedItem(exerciseID: "bench", targetSets: 3, targetReps: RepRange(min: 6, max: 8),
                    targetLoadKg: 60, restSeconds: 90, coachNote: "")
    }

    private func flyItem() -> PlannedItem {
        PlannedItem(exerciseID: "fly", targetSets: 3, targetReps: RepRange(min: 10, max: 15),
                    targetLoadKg: 15, restSeconds: 60, coachNote: "")
    }

    private func plannedSession(_ items: [PlannedItem]) -> PlannedSession {
        PlannedSession(id: UUID(), order: 0, focusMuscles: [.chest], items: items)
    }

    // MARK: - Assertions

    @Test func progressionAppliedNoTrimUnderGenerousTime() {
        let finalizer = RuleEngineFinalizer(catalog: catalog(), repository: repository())
        let result = finalizer.finalize(plannedSession([benchItem(), flyItem()]),
                                        energy: .normal, timeAvailableMin: 999)

        #expect(result.session.items.count == 2)
        let bench = result.session.items.first { $0.exerciseID == "bench" }
        #expect((bench?.targetLoadKg ?? 0) > 60)
        #expect(result.perItemRationale["bench"]?.isEmpty == false)
    }

    @Test func beatEnergyDropsTheLastIsolationItem() {
        let finalizer = RuleEngineFinalizer(catalog: catalog(), repository: repository())
        let result = finalizer.finalize(plannedSession([benchItem(), flyItem()]),
                                        energy: .beat, timeAvailableMin: 999)

        let ids = result.session.items.map(\.exerciseID)
        #expect(ids.contains("bench"))
        #expect(!ids.contains("fly"))
    }

    @Test func tightTimeTrimsTrailingItems() {
        let finalizer = RuleEngineFinalizer(catalog: catalog(), repository: repository())
        let result = finalizer.finalize(plannedSession([benchItem(), flyItem()]),
                                        energy: .normal, timeAvailableMin: 5)

        #expect(result.session.items.count < 2)
    }

    @Test func noHistoryKeepsNilLoadAndHoldRationale() {
        let finalizer = RuleEngineFinalizer(catalog: catalog(), repository: repository())
        let curl = PlannedItem(exerciseID: "curl", targetSets: 3, targetReps: RepRange(min: 8, max: 12),
                               targetLoadKg: nil, restSeconds: 60, coachNote: "")
        let result = finalizer.finalize(plannedSession([benchItem(), curl]),
                                        energy: .normal, timeAvailableMin: 999)

        let curlOut = result.session.items.first { $0.exerciseID == "curl" }
        #expect(curlOut != nil)
        #expect(curlOut?.targetLoadKg == nil)
        #expect(result.perItemRationale["curl"] == "no history yet")
    }
}
