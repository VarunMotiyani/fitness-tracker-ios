import Testing
import Foundation
import FitnessDomain
import Metrics
@testable import RuleEngine

private func perf(_ sets: [(reps: Int, load: Double)], feel: Feel?) -> ExercisePerformance {
    let now = Date()
    let snapshots = sets.map { s in
        LoggedSetSnapshot(
            targetReps: s.reps, targetLoadKg: s.load,
            actualReps: s.reps, actualLoadKg: s.load,
            startedAt: now, completedAt: now,
            restBeforeSec: 0, rpe: nil,
            isWarmup: false, isDropSet: false, toFailure: false, assisted: false
        )
    }
    return ExercisePerformance(exerciseID: "ex", date: now, sets: snapshots, feel: feel)
}

private let rule = ProgressionRule()
private let range = RepRange(min: 8, max: 10)

@Test func noHistoryHolds() {
    let d = rule.next(currentTargetLoadKg: 100, currentTargetSets: 3,
                      repRange: range, mechanic: .compound, lastPerformance: nil)
    #expect(d.direction == .hold)
    #expect(d.targetLoadKg == 100)
    #expect(d.targetSets == 3)
    #expect(d.rationale == "no history yet")
}

@Test func easyAllMaxedCompoundIncreases() {
    let last = perf([(10, 100), (10, 100), (10, 100)], feel: .easy)
    let d = rule.next(currentTargetLoadKg: 100, currentTargetSets: 3,
                      repRange: range, mechanic: .compound, lastPerformance: last)
    #expect(d.direction == .increaseLoad)
    #expect(d.targetLoadKg == (100.0 * 1.05 / 2.5).rounded() * 2.5)
    #expect(d.targetLoadKg <= 100.0 * 1.10)
    #expect(d.targetSets == 3)
}

@Test func easyAllMaxedIsolationSmallStepStaysWithinCap() {
    let last = perf([(10, 40), (10, 40)], feel: .easy)
    let d = rule.next(currentTargetLoadKg: 40, currentTargetSets: 2,
                      repRange: range, mechanic: .isolation, lastPerformance: last)
    #expect(d.direction == .increaseLoad)
    #expect(d.targetLoadKg >= 40)
    #expect(d.targetLoadKg <= 40.0 * 1.10)
}

@Test func rightMidRangeHolds() {
    let last = perf([(9, 100), (9, 100), (8, 100)], feel: .right)
    let d = rule.next(currentTargetLoadKg: 100, currentTargetSets: 3,
                      repRange: range, mechanic: .compound, lastPerformance: last)
    #expect(d.direction == .hold)
    #expect(d.targetLoadKg == 100)
    #expect(d.targetSets == 3)
}

@Test func rightButAllMaxedGivesSmallBump() {
    let last = perf([(10, 100), (11, 100), (10, 100)], feel: .right)
    let d = rule.next(currentTargetLoadKg: 100, currentTargetSets: 3,
                      repRange: range, mechanic: .compound, lastPerformance: last)
    #expect(d.direction == .increaseLoad)
    // halved step: 0.025 -> 100 * 1.025 = 102.5 rounds to 102.5
    #expect(d.targetLoadKg == (100.0 * 1.025 / 2.5).rounded() * 2.5)
    #expect(d.targetLoadKg <= 100.0 * 1.10)
    #expect(d.targetLoadKg >= 100)
}

@Test func easyButNotAllMaxedHolds() {
    let last = perf([(10, 100), (9, 100), (10, 100)], feel: .easy)
    let d = rule.next(currentTargetLoadKg: 100, currentTargetSets: 3,
                      repRange: range, mechanic: .compound, lastPerformance: last)
    #expect(d.direction == .hold)
    #expect(d.targetLoadKg == 100)
}

@Test func brutalWithSetBelowMinDecreases() {
    let last = perf([(8, 100), (6, 100), (5, 100)], feel: .brutal)
    let d = rule.next(currentTargetLoadKg: 100, currentTargetSets: 3,
                      repRange: range, mechanic: .compound, lastPerformance: last)
    #expect(d.direction == .decreaseLoad)
    #expect(d.targetLoadKg >= 100.0 * 0.85)
    #expect(d.targetLoadKg < 100)
    #expect(d.targetSets == 3)
}

@Test func belowMinDecreasesRegardlessOfFeel() {
    let last = perf([(8, 100), (5, 100)], feel: .right)
    let d = rule.next(currentTargetLoadKg: 100, currentTargetSets: 3,
                      repRange: range, mechanic: .isolation, lastPerformance: last)
    #expect(d.direction == .decreaseLoad)
    #expect(d.targetLoadKg >= 100.0 * 0.85)
}

@Test func brutalButAllInRangeHolds() {
    let last = perf([(8, 100), (9, 100), (10, 100)], feel: .brutal)
    let d = rule.next(currentTargetLoadKg: 100, currentTargetSets: 3,
                      repRange: range, mechanic: .compound, lastPerformance: last)
    #expect(d.direction == .hold)
    #expect(d.targetLoadKg == 100)
    #expect(d.targetSets == 3)
}

@Test func neverAddsSetAcrossAllScenarios() {
    let scenarios: [ExercisePerformance?] = [
        nil,
        perf([(10, 100), (10, 100), (10, 100)], feel: .easy),
        perf([(10, 40), (10, 40)], feel: .easy),
        perf([(9, 100), (9, 100), (8, 100)], feel: .right),
        perf([(10, 100), (11, 100), (10, 100)], feel: .right),
        perf([(10, 100), (9, 100), (10, 100)], feel: .easy),
        perf([(8, 100), (6, 100), (5, 100)], feel: .brutal),
        perf([(8, 100), (9, 100), (10, 100)], feel: .brutal),
        perf([(8, 100), (5, 100)], feel: .right),
        perf([(9, 100)], feel: nil),
        perf([(12, 100), (12, 100)], feel: nil),
    ]
    for (mechanic, s) in scenarios.flatMap({ s in [Mechanic.compound, .isolation, .unknown].map { ($0, s) } }) {
        let d = rule.next(currentTargetLoadKg: 100, currentTargetSets: 3,
                          repRange: range, mechanic: mechanic, lastPerformance: s)
        #expect(d.direction != .addSet)
    }
}

@Test func decreaseIsRoundedToStep() {
    let last = perf([(4, 100)], feel: .brutal)
    let d = rule.next(currentTargetLoadKg: 100, currentTargetSets: 3,
                      repRange: range, mechanic: .compound, lastPerformance: last)
    #expect(d.direction == .decreaseLoad)
    #expect((d.targetLoadKg / 2.5).rounded() * 2.5 == d.targetLoadKg)
}
