import Testing
import Foundation
import FitnessDomain
import ExerciseCatalog
import Metrics
@testable import RuleEngine

// MARK: - Fixtures

private func catalog() -> CatalogStore {
    func ex(_ id: String, _ muscle: MuscleGroup, _ equipment: Equipment) -> Exercise {
        Exercise(id: id, name: id, primaryMuscle: muscle, secondaryMuscles: [],
                 equipment: equipment, mechanic: .compound, force: nil,
                 difficulty: .beginner, isUnilateral: false, instructions: [], imagePaths: [])
    }
    return CatalogStore(exercises: [
        ex("bench", .chest, .barbell),
        ex("cablefly", .chest, .cable),
        ex("row", .back, .barbell),
        ex("curl", .biceps, .dumbbell),
        ex("legpress", .quads, .machine),
        ex("kbswing", .glutes, .kettlebell),
    ])
}

private func item(_ id: String, sets: Int = 3, reps: RepRange = RepRange(min: 8, max: 12),
                  loadKg: Double? = nil, rest: Int = 90) -> PlannedItem {
    PlannedItem(exerciseID: id, targetSets: sets, targetReps: reps, targetLoadKg: loadKg,
                restSeconds: rest, coachNote: "")
}

private func session(_ items: [PlannedItem]) -> PlannedSession {
    PlannedSession(id: UUID(), order: 0, focusMuscles: [], items: items)
}

private func workingSet(loadKg: Double, isWarmup: Bool = false) -> LoggedSetSnapshot {
    LoggedSetSnapshot(targetReps: 8, targetLoadKg: loadKg, actualReps: 8, actualLoadKg: loadKg,
                      startedAt: Date(), completedAt: Date(), restBeforeSec: 90, rpe: nil,
                      isWarmup: isWarmup, isDropSet: false, toFailure: false, assisted: false)
}

private func performance(_ id: String, working: Double, warmup: Double? = nil) -> ExercisePerformance {
    var sets: [LoggedSetSnapshot] = []
    if let warmup { sets.append(workingSet(loadKg: warmup, isWarmup: true)) }
    sets.append(workingSet(loadKg: working))
    return ExercisePerformance(exerciseID: id, date: Date(), sets: sets, feel: nil)
}

private func run(_ guardrail: FinalizeGuardrail, _ finalized: PlannedSession,
                 experience: ExperienceLevel = .intermediate,
                 excludedIDs: Set<String> = [],
                 excludedMuscles: Set<MuscleGroup> = [],
                 equipment: Set<Equipment> = [.barbell, .dumbbell, .machine, .cable],
                 last: [String: ExercisePerformance] = [:],
                 timeMin: Int = 120,
                 inc: Double = 0.10, dec: Double = 0.15) -> GuardrailReport {
    guardrail.check(finalized: finalized, experience: experience,
                    excludedExerciseIDs: excludedIDs, excludedMuscles: excludedMuscles,
                    availableEquipment: equipment, lastPerformances: last,
                    timeAvailableMin: timeMin,
                    maxIncreaseFraction: inc, maxDecreaseFraction: dec)
}

// MARK: - Tests

@Test func cleanSessionPassesUnchanged() {
    let guardrail = FinalizeGuardrail(catalog: catalog())
    let finalized = session([item("bench", sets: 10), item("row", sets: 12)])
    let report = run(guardrail, finalized)
    #expect(report.violations.isEmpty)
    #expect(report.clampedSession == finalized)
}

@Test func loadJumpReportedAndClamped() {
    let guardrail = FinalizeGuardrail(catalog: catalog())
    let finalized = session([item("bench", sets: 10, loadKg: 150)])
    let report = run(guardrail, finalized, last: ["bench": performance("bench", working: 100, warmup: 999)])
    #expect(report.violations.contains(.loadJumpTooLarge(exerciseID: "bench", proposedKg: 150, cappedKg: 110)))
    #expect(report.clampedSession.items[0].targetLoadKg == 110)
}

@Test func loadDropReportedAndClamped() {
    let guardrail = FinalizeGuardrail(catalog: catalog())
    let finalized = session([item("bench", sets: 10, loadKg: 50)])
    let report = run(guardrail, finalized, last: ["bench": performance("bench", working: 100)])
    #expect(report.violations.contains(.loadDropTooLarge(exerciseID: "bench", proposedKg: 50, cappedKg: 85)))
    #expect(report.clampedSession.items[0].targetLoadKg == 85)
}

@Test func weeklyVolumeOverMrvReportedAndScaledDown() {
    let guardrail = FinalizeGuardrail(catalog: catalog())
    let finalized = session([item("bench", sets: 15), item("cablefly", sets: 15)])
    let report = run(guardrail, finalized)
    #expect(report.violations.contains(.weeklyVolumeOutOfBand(muscle: .chest, sets: 30, mev: 8, mrv: 22)))
    #expect(report.clampedSession.items.allSatisfy { $0.targetSets == 11 })
}

@Test func weeklyVolumeUnderMevReportedButNotScaled() {
    let guardrail = FinalizeGuardrail(catalog: catalog())
    let finalized = session([item("curl", sets: 2)])
    let report = run(guardrail, finalized)
    #expect(report.violations.contains(.weeklyVolumeOutOfBand(muscle: .biceps, sets: 2, mev: 6, mrv: 20)))
    // Report-only: a single session is expected to be below weekly MEV.
    #expect(report.clampedSession.items[0].targetSets == 2)
}

@Test func realisticPushSessionPassesUnchanged() {
    let guardrail = FinalizeGuardrail(catalog: catalog())
    // bench 4 + cablefly 3 = 7 chest sets, under intermediate chest weekly MEV 8.
    let finalized = session([item("bench", sets: 4), item("cablefly", sets: 3)])
    let report = run(guardrail, finalized)
    // Sets are never inflated toward weekly MEV.
    #expect(report.clampedSession.items.map(\.targetSets) == [4, 3])
    #expect(report.clampedSession.items.map(\.exerciseID) == ["bench", "cablefly"])
    // The only violation permitted here is the report-only under-MEV note.
    #expect(report.violations.allSatisfy {
        if case .weeklyVolumeOutOfBand(.chest, 7, 8, 22) = $0 { return true } else { return false }
    })
}

@Test func repTargetOutOfRangeReportedAndClamped() {
    let guardrail = FinalizeGuardrail(catalog: catalog())
    let finalized = session([item("bench", sets: 10, reps: RepRange(min: 1, max: 25))])
    let report = run(guardrail, finalized)
    #expect(report.violations.contains(.repTargetOutOfRange(
        exerciseID: "bench",
        target: RepRange(min: 1, max: 25),
        allowed: RepRange(min: 3, max: 20))))
    #expect(report.clampedSession.items[0].targetReps == RepRange(min: 3, max: 20))
}

@Test func excludedExercisesReportedAndDropped() {
    let guardrail = FinalizeGuardrail(catalog: catalog())
    let finalized = session([
        item("bench", sets: 10),
        item("curl", sets: 8),      // excluded by id
        item("ghost", sets: 3),     // unknown to catalog
        item("row", sets: 8),       // excluded by muscle
        item("kbswing", sets: 8),   // equipment unavailable
    ])
    let report = run(guardrail, finalized,
                     excludedIDs: ["curl"], excludedMuscles: [.back])
    let excluded = report.violations.filter {
        if case .excludedExercise = $0 { return true } else { return false }
    }
    #expect(excluded.count == 4)
    #expect(report.violations.contains(.excludedExercise(exerciseID: "curl")))
    #expect(report.violations.contains(.excludedExercise(exerciseID: "ghost")))
    #expect(report.violations.contains(.excludedExercise(exerciseID: "row")))
    #expect(report.violations.contains(.excludedExercise(exerciseID: "kbswing")))
    #expect(report.clampedSession.items.map(\.exerciseID) == ["bench"])
}

@Test func sessionTooLongReportedAndTrimmed() {
    let guardrail = FinalizeGuardrail(catalog: catalog())
    let finalized = session([
        item("bench", sets: 10, rest: 200),
        item("row", sets: 10, rest: 200),
        item("legpress", sets: 10, rest: 200),
    ])
    let report = run(guardrail, finalized, timeMin: 40)
    #expect(report.violations.contains(.sessionTooLong(estimatedMin: 120, availableMin: 40)))
    #expect(report.clampedSession.items.count == 1)
    #expect(report.clampedSession.items[0].exerciseID == "bench")
}
