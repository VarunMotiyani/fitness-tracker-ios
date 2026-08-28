import FitnessDomain
import Metrics

/// Which way the working load should move for the next session.
public enum ProgressionDirection: Sendable, Equatable {
    case increaseLoad
    case hold
    case decreaseLoad
    /// Reserved for a later volume rule (Task 2c). `ProgressionRule` never returns it.
    case addSet
}

/// The concrete recommendation produced by `ProgressionRule`.
public struct ProgressionDecision: Sendable, Equatable {
    public let direction: ProgressionDirection
    public let targetLoadKg: Double
    public let targetSets: Int
    public let rationale: String

    public init(direction: ProgressionDirection, targetLoadKg: Double, targetSets: Int, rationale: String) {
        self.direction = direction
        self.targetLoadKg = targetLoadKg
        self.targetSets = targetSets
        self.rationale = rationale
    }
}

/// Deterministic "should the weight go up / hold / down" decision.
///
/// Also the offline fallback for the AI session coach: given the last logged
/// performance of an exercise, it decides the next target load using the
/// feel × reps-hit matrix from the Phase 2a brief.
public struct ProgressionRule: Sendable {
    private let maxIncreaseFraction: Double
    private let maxDecreaseFraction: Double

    public init(maxIncreaseFraction: Double = 0.10, maxDecreaseFraction: Double = 0.15) {
        self.maxIncreaseFraction = maxIncreaseFraction
        self.maxDecreaseFraction = maxDecreaseFraction
    }

    public func next(
        currentTargetLoadKg: Double,
        currentTargetSets: Int,
        repRange: RepRange,
        mechanic: Mechanic,
        lastPerformance: ExercisePerformance?
    ) -> ProgressionDecision {
        func hold(_ rationale: String, load: Double = currentTargetLoadKg) -> ProgressionDecision {
            ProgressionDecision(direction: .hold, targetLoadKg: load,
                                targetSets: currentTargetSets, rationale: rationale)
        }

        guard let last = lastPerformance else {
            return hold("no history yet")
        }

        let working = last.sets.filter { !$0.isWarmup }
        guard !working.isEmpty else {
            return hold("no working sets logged last time — repeat the load")
        }

        let allHitMax = working.allSatisfy { $0.actualReps >= repRange.max }
        let anyBelowMin = working.contains { $0.actualReps < repRange.min }
        let allInRange = working.allSatisfy { $0.actualReps >= repRange.min && $0.actualReps <= repRange.max }
        let baseStep = mechanic == .compound ? 0.05 : 0.025

        // Decrease branch: brutal effort, or reps fell out the bottom of the range.
        if last.feel == .brutal || anyBelowMin {
            if last.feel == .brutal, !anyBelowMin, allInRange {
                return hold("'brutal' feel but every working set landed in the rep range — hold and repeat")
            }
            let raw = currentTargetLoadKg * (1 - 0.05)
            let floor = currentTargetLoadKg * (1 - maxDecreaseFraction)
            let newLoad = roundToStep(max(raw, floor))
            let rationale = anyBelowMin
                ? "a working set fell below the rep range — back off the load"
                : "'brutal' feel — back off the load"
            return ProgressionDecision(direction: .decreaseLoad, targetLoadKg: newLoad,
                                       targetSets: currentTargetSets, rationale: rationale)
        }

        // Increase branch: felt easy and every working set reached the top of the range.
        if last.feel == .easy, allHitMax {
            let newLoad = roundToStep(cappedIncrease(from: currentTargetLoadKg, step: baseStep))
            return ProgressionDecision(direction: .increaseLoad, targetLoadKg: newLoad,
                                       targetSets: currentTargetSets,
                                       rationale: "'easy' feel and every working set hit the top of the rep range — add load")
        }

        // Small-bump branch: didn't feel easy, but still maxed every set — nudge up at half step.
        if allHitMax {
            let newLoad = roundToStep(cappedIncrease(from: currentTargetLoadKg, step: baseStep / 2))
            return ProgressionDecision(direction: .increaseLoad, targetLoadKg: newLoad,
                                       targetSets: currentTargetSets,
                                       rationale: "hit the top of the rep range on every set without an 'easy' feel — small bump")
        }

        // Hold branch: everything else stays put.
        let rationale = last.feel == .easy
            ? "'easy' feel but the top of the rep range wasn't reached on every set — repeat the load"
            : "reps within range — repeat the load"
        return hold(rationale)
    }

    private func cappedIncrease(from load: Double, step: Double) -> Double {
        let raw = load * (1 + step)
        let ceiling = load * (1 + maxIncreaseFraction)
        return min(raw, ceiling)
    }

    private func roundToStep(_ x: Double) -> Double {
        (x / 2.5).rounded() * 2.5
    }
}
