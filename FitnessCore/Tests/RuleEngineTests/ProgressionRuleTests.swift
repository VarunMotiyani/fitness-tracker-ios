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

@Test func capsBindWhenTight() {
    let tight = ProgressionRule(maxIncreaseFraction: 0.02, maxDecreaseFraction: 0.01)

    // Increase: easy + all-max compound would bump 5%, but the 2% ceiling binds.
    let up = tight.next(currentTargetLoadKg: 200, currentTargetSets: 3, repRange: range,
                        mechanic: .compound,
                        lastPerformance: perf([(10, 200), (10, 200)], feel: .easy))
    #expect(up.direction == .increaseLoad)
    #expect(up.targetLoadKg <= 200.0 * 1.02)          // never breaches the ceiling
    #expect(up.targetLoadKg < (200.0 * 1.05 / 2.5).rounded() * 2.5)  // cap actually bound

    // Decrease: brutal would back off 5%, but the 1% floor binds.
    let down = tight.next(currentTargetLoadKg: 200, currentTargetSets: 3, repRange: range,
                          mechanic: .compound,
                          lastPerformance: perf([(4, 200)], feel: .brutal))
    #expect(down.direction == .decreaseLoad)
    #expect(down.targetLoadKg >= 200.0 * 0.99)        // never breaches the floor
    #expect(down.targetLoadKg > 200.0 * 0.95)         // cap actually bound
}

@Test func brutalWithRepAboveMaxStillDecreases() {
    // 12 > repRange.max (10), nothing below min -> not the "all in range" hold.
    let last = perf([(12, 100), (9, 100)], feel: .brutal)
    let d = rule.next(currentTargetLoadKg: 100, currentTargetSets: 3,
                      repRange: range, mechanic: .compound, lastPerformance: last)
    #expect(d.direction == .decreaseLoad)
}

@Test func emptyWorkingSetListHoldsWithRationale() {
    let last = perf([], feel: .right)
    let d = rule.next(currentTargetLoadKg: 100, currentTargetSets: 3,
                      repRange: range, mechanic: .compound, lastPerformance: last)
    #expect(d.direction == .hold)
    #expect(d.targetLoadKg == 100)
    #expect(d.rationale == "no working sets logged last time — repeat the load")
}

@Test func onlyZeroRepSetsTreatedAsNoWorkingSets() {
    let last = perf([(0, 100), (0, 100)], feel: .easy)
    let d = rule.next(currentTargetLoadKg: 100, currentTargetSets: 3,
                      repRange: range, mechanic: .compound, lastPerformance: last)
    #expect(d.direction == .hold)
    #expect(d.rationale == "no working sets logged last time — repeat the load")
}

@Test func feelNilMidRangeHolds() {
    let last = perf([(9, 100), (9, 100)], feel: nil)
    let d = rule.next(currentTargetLoadKg: 100, currentTargetSets: 3,
                      repRange: range, mechanic: .compound, lastPerformance: last)
    #expect(d.direction == .hold)
    #expect(d.targetLoadKg == 100)
}

@Test func decreaseIsRoundedToStep() {
    let last = perf([(4, 100)], feel: .brutal)
    let d = rule.next(currentTargetLoadKg: 100, currentTargetSets: 3,
                      repRange: range, mechanic: .compound, lastPerformance: last)
    #expect(d.direction == .decreaseLoad)
    #expect((d.targetLoadKg / 2.5).rounded() * 2.5 == d.targetLoadKg)
}

// MARK: - openGym Parity Tests

struct OpenGymProgressionParityTests {
    private let now = Date()

    private func makeReading(goal: Int, reps: [Int], weight: Double, ok: Bool) -> SessionReading {
        SessionReading(
            mode: .reps,
            goal: goal,
            repsPerSet: reps,
            heldPerSet: [],
            weightKg: weight,
            count: reps.count,
            low: reps.min() ?? 0,
            amrap: reps.last ?? 0,
            ok: ok
        )
    }

    @Test func linearProgressionIncreasesOnSuccess() {
        let history = [makeReading(goal: 10, reps: [10, 10, 10], weight: 100, ok: true)]
        let target = PrescriptionTarget(sets: 3, reps: 10, loadKg: 100, incKg: 2.5, policy: .linear)
        let p = ProgressionRule().next(current: target, mechanic: .compound, history: history)

        #expect(p.kind == .up)
        #expect(p.weightKg == 102.5)
        #expect(p.why.render().contains("2.5 kg more"))
    }

    @Test func linearProgressionHoldsUntilThreeMissesThenDeloads() {
        let rule = ProgressionRule()
        let target = PrescriptionTarget(sets: 3, reps: 10, loadKg: 100, incKg: 2.5, policy: .linear)
        let miss = makeReading(goal: 10, reps: [9, 8, 8], weight: 100, ok: false)

        let p1 = rule.next(current: target, mechanic: .compound, history: [miss])
        #expect(p1.kind == .hold)
        #expect(p1.weightKg == 100)

        let p2 = rule.next(current: target, mechanic: .compound, history: [miss, miss])
        #expect(p2.kind == .hold)

        let p3 = rule.next(current: target, mechanic: .compound, history: [miss, miss, miss])
        #expect(p3.kind == .deload)
        #expect(p3.weightKg == 90.0) // 100 * 0.9 = 90
    }

    @Test func greyskullDeloadsOnFirstMiss() {
        let miss = makeReading(goal: 5, reps: [5, 5, 4], weight: 100, ok: false)
        let target = PrescriptionTarget(sets: 3, reps: 5, loadKg: 100, incKg: 2.5, policy: .greyskull)
        let p = ProgressionRule().next(current: target, mechanic: .compound, history: [miss])

        #expect(p.kind == .deload)
        #expect(p.weightKg == 90.0)
    }

    @Test func greyskullDoubleJumpWhenAMRAPDoubled() {
        let bigSuccess = makeReading(goal: 5, reps: [5, 5, 10], weight: 100, ok: true)
        let target = PrescriptionTarget(sets: 3, reps: 5, loadKg: 100, incKg: 2.5, policy: .greyskull)
        let p = ProgressionRule().next(current: target, mechanic: .compound, history: [bigSuccess])

        #expect(p.kind == .up)
        #expect(p.weightKg == 105.0) // 2.5 * 2 = 5.0 jump
        #expect(p.why.render().contains("double jump"))
    }

    @Test func doubleProgressionClimbsThenResetsReps() {
        let rule = ProgressionRule()
        let target = PrescriptionTarget(sets: 3, reps: 12, repsMin: 8, loadKg: 80, incKg: 2.5, policy: .double)

        // Success: hit top of range (12) -> weight goes up, reps reset to bottom (8)
        let success = makeReading(goal: 12, reps: [12, 12, 12], weight: 80, ok: true)
        let pUp = rule.next(current: target, mechanic: .compound, history: [success])
        #expect(pUp.kind == .up)
        #expect(pUp.weightKg == 82.5)
        #expect(pUp.reps == 8)

        // Hold: low was 9 reps -> aim for 10
        let mid = makeReading(goal: 12, reps: [11, 10, 9], weight: 80, ok: false)
        let pHold = rule.next(current: target, mechanic: .compound, history: [mid])
        #expect(pHold.kind == .hold)
        #expect(pHold.reps == 10)
    }

    @Test func bodyweightProgressionGrowsRepsAndSets() {
        let rule = ProgressionRule()
        let target = PrescriptionTarget(sets: 3, reps: 10, repsMax: 20, loadKg: 0, policy: .linear)

        // 1. Success with reps below max -> rep increment
        let r1 = makeReading(goal: 10, reps: [10, 10, 10], weight: 0, ok: true)
        let p1 = rule.next(current: target, mechanic: .compound, history: [r1])
        #expect(p1.kind == .up)
        #expect(p1.reps == 11)
        #expect(p1.weightKg == 0)

        // 2. Goal reached top of range (20) -> add set (from 3 to 4), reset reps to bottom (10)
        let r2 = makeReading(goal: 20, reps: [20, 20, 20], weight: 0, ok: true)
        let p2 = rule.next(current: target, mechanic: .compound, history: [r2])
        #expect(p2.kind == .up)
        #expect(p2.sets == 4)
        #expect(p2.reps == 10)

        // 3. Max sets reached (6 sets) -> hold and advise harder variation
        let maxSetsTarget = PrescriptionTarget(sets: 6, reps: 10, repsMax: 20, loadKg: 0, policy: .linear)
        let r3 = makeReading(goal: 20, reps: [20, 20, 20, 20, 20, 20], weight: 0, ok: true)
        let p3 = rule.next(current: maxSetsTarget, mechanic: .compound, history: [r3])
        #expect(p3.kind == .hold)
        #expect(p3.why.render().contains("harder variation"))
    }
}
