import FitnessDomain
import Metrics

/// Supported progression policies (ported from openGym + hybrid AI coach)
public enum ProgressionPolicy: String, Sendable, Codable, CaseIterable {
    case standardLinear    // Default: feel × reps-hit rule (+5% compound, +2.5% isolation)
    case doubleProgression // Climb reps through range, then bump load and reset reps
    case greyskullLP       // Straight sets + final AMRAP; double jump on 2x reps, 10% deload on failure
    case deload            // Explicit 10% deload backoff
    
    public var displayName: String {
        switch self {
        case .standardLinear: return "Standard Linear"
        case .doubleProgression: return "Double Progression"
        case .greyskullLP: return "Greyskull LP (AMRAP)"
        case .deload: return "Deload"
        }
    }
}

/// Which way the working load should move for the next session.
public enum ProgressionDirection: Sendable, Equatable {
    case increaseLoad
    case hold
    case decreaseLoad
    case addSet
}

/// The concrete recommendation produced by `ProgressionRule`.
public struct ProgressionDecision: Sendable, Equatable {
    public let direction: ProgressionDirection
    public let targetLoadKg: Double
    public let targetSets: Int
    public let targetReps: RepRange?
    public let rationale: String

    public init(
        direction: ProgressionDirection,
        targetLoadKg: Double,
        targetSets: Int,
        targetReps: RepRange? = nil,
        rationale: String
    ) {
        self.direction = direction
        self.targetLoadKg = targetLoadKg
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.rationale = rationale
    }
}

/// Deterministic "should the weight go up / hold / down" decision engine.
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
        lastPerformance: ExercisePerformance?,
        policy: ProgressionPolicy = .standardLinear
    ) -> ProgressionDecision {
        func hold(_ rationale: String, load: Double = currentTargetLoadKg, reps: RepRange? = nil) -> ProgressionDecision {
            ProgressionDecision(
                direction: .hold,
                targetLoadKg: load,
                targetSets: currentTargetSets,
                targetReps: reps ?? repRange,
                rationale: rationale
            )
        }

        guard let last = lastPerformance else {
            return hold("no history yet")
        }

        let working = last.sets.filter { $0.isWorkingSet }
        guard !working.isEmpty else {
            return hold("no working sets logged last time — repeat the load")
        }

        let allHitMax = working.allSatisfy { $0.actualReps >= repRange.max }
        let anyBelowMin = working.contains { $0.actualReps < repRange.min }
        let allInRange = working.allSatisfy { $0.actualReps >= repRange.min && $0.actualReps <= repRange.max }
        let baseStep = mechanic == .compound ? 0.05 : 0.025

        switch policy {
        case .deload:
            let newLoad = max(2.5, roundToStep(currentTargetLoadKg * 0.90))
            return ProgressionDecision(
                direction: .decreaseLoad,
                targetLoadKg: newLoad,
                targetSets: max(1, currentTargetSets - 1),
                targetReps: repRange,
                rationale: "planned deload — 10% load reduction and reduced volume"
            )

        case .doubleProgression:
            // Double Progression: work within rep range at same load; when all sets hit repRange.max, bump load and reset to min
            if allHitMax {
                let newLoad = cappedIncrease(from: currentTargetLoadKg, step: baseStep)
                return ProgressionDecision(
                    direction: .increaseLoad,
                    targetLoadKg: newLoad,
                    targetSets: currentTargetSets,
                    targetReps: repRange,
                    rationale: "hit top of rep range (\(repRange.max)) on all sets — advance load and reset to \(repRange.min) reps"
                )
            } else if anyBelowMin {
                let newLoad = cappedDecrease(from: currentTargetLoadKg)
                return ProgressionDecision(
                    direction: .decreaseLoad,
                    targetLoadKg: newLoad,
                    targetSets: currentTargetSets,
                    targetReps: repRange,
                    rationale: "fell below bottom of rep range (\(repRange.min)) — back off load"
                )
            } else {
                return hold("progressing reps inside \(repRange.min)-\(repRange.max) range at current load")
            }

        case .greyskullLP:
            // Greyskull LP: straight sets + AMRAP final set
            if let lastSet = working.last {
                if lastSet.actualReps >= repRange.max * 2 {
                    // Double jump if double reps achieved
                    let newLoad = cappedIncrease(from: currentTargetLoadKg, step: baseStep * 2)
                    return ProgressionDecision(
                        direction: .increaseLoad,
                        targetLoadKg: newLoad,
                        targetSets: currentTargetSets,
                        targetReps: repRange,
                        rationale: "Greyskull AMRAP exceeded 2x target reps (\(lastSet.actualReps) reps) — double load increase!"
                    )
                } else if lastSet.actualReps >= repRange.max && !anyBelowMin {
                    let newLoad = cappedIncrease(from: currentTargetLoadKg, step: baseStep)
                    return ProgressionDecision(
                        direction: .increaseLoad,
                        targetLoadKg: newLoad,
                        targetSets: currentTargetSets,
                        targetReps: repRange,
                        rationale: "Greyskull target achieved on all sets including AMRAP — add load"
                    )
                } else if anyBelowMin || last.feel == .brutal {
                    // Greyskull 10% reset on failure
                    let newLoad = max(2.5, roundToStep(currentTargetLoadKg * 0.90))
                    return ProgressionDecision(
                        direction: .decreaseLoad,
                        targetLoadKg: newLoad,
                        targetSets: currentTargetSets,
                        targetReps: repRange,
                        rationale: "Greyskull missed reps/failure — reset load by 10% to rebuild momentum"
                    )
                }
            }
            return hold("reps on track — repeat load")

        case .standardLinear:
            // Standard Linear Progression
            if last.feel == .brutal || anyBelowMin {
                if last.feel == .brutal, !anyBelowMin, allInRange {
                    return hold("'brutal' feel but every working set landed in the rep range — hold and repeat")
                }
                let newLoad = cappedDecrease(from: currentTargetLoadKg)
                let rationale = anyBelowMin
                    ? "a working set fell below the rep range — back off the load"
                    : "'brutal' feel — back off the load"
                return ProgressionDecision(
                    direction: .decreaseLoad,
                    targetLoadKg: newLoad,
                    targetSets: currentTargetSets,
                    targetReps: repRange,
                    rationale: rationale
                )
            }

            if last.feel == .easy, allHitMax {
                let newLoad = cappedIncrease(from: currentTargetLoadKg, step: baseStep)
                return ProgressionDecision(
                    direction: .increaseLoad,
                    targetLoadKg: newLoad,
                    targetSets: currentTargetSets,
                    targetReps: repRange,
                    rationale: "'easy' feel and every working set hit the top of the rep range — add load"
                )
            }

            if allHitMax {
                let newLoad = cappedIncrease(from: currentTargetLoadKg, step: baseStep / 2)
                return ProgressionDecision(
                    direction: .increaseLoad,
                    targetLoadKg: newLoad,
                    targetSets: currentTargetSets,
                    targetReps: repRange,
                    rationale: "hit the top of the rep range on every set without an 'easy' feel — small bump"
                )
            }

            let rationale = last.feel == .easy
                ? "'easy' feel but the top of the rep range wasn't reached on every set — repeat the load"
                : "reps within range — repeat the load"
            return hold(rationale)
        }
    }

    private func cappedIncrease(from load: Double, step: Double) -> Double {
        let raw = load * (1 + step)
        let ceiling = load * (1 + maxIncreaseFraction)
        if raw >= ceiling { return floorToStep(ceiling) }
        return roundToStep(raw)
    }

    private func cappedDecrease(from load: Double) -> Double {
        let raw = load * (1 - 0.05)
        let floor = load * (1 - maxDecreaseFraction)
        if raw <= floor { return ceilToStep(floor) }
        return roundToStep(raw)
    }

    private func roundToStep(_ x: Double) -> Double { (x / 2.5).rounded() * 2.5 }
    private func floorToStep(_ x: Double) -> Double { (x / 2.5).rounded(.down) * 2.5 }
    private func ceilToStep(_ x: Double) -> Double { (x / 2.5).rounded(.up) * 2.5 }
}
