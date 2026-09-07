import Foundation
import FitnessDomain
import Metrics

/// Supported progression policies matching openGym + hybrid AI coach
public enum ProgressionPolicy: String, Sendable, Codable, CaseIterable {
    case off
    case linear            // openGym standard linear progression (hit all reps -> add weight)
    case greyskull         // Greyskull LP: straight sets + AMRAP; 2x goal -> double jump, fail -> 10% deload
    case double            // Double progression: climb reps through range, then bump weight and reset reps
    case time              // Time progression: hold every set -> add duration
    case standardLinear    // Hybrid AI Coach feel-based linear
    case deload            // Explicit deload

    public var displayName: String {
        switch self {
        case .off: return "No automatic progression"
        case .linear: return "Linear progression"
        case .greyskull: return "Greyskull LP"
        case .double: return "Double progression"
        case .time: return "Add time"
        case .standardLinear: return "AI Coach Linear"
        case .deload: return "Deload"
        }
    }
}

public enum WhyTemplate: Sendable, Equatable {
    case baseline
    case heldEverySet(incSec: Int)
    case timeShortDeload(stalls: Int, sec: Int)
    case timeShortHold
    case bwHoldClean
    case bwAddSet(goal: Int, bottom: Int)
    case bwAddWeightOrHarder(sets: Int, goal: Int)
    case bwMoreReps(next: Int)
    case doubleUp(inc: Double, unit: String, bottom: Int)
    case doubleDeload(stalls: Int, load: Double, unit: String)
    case doubleHold(aim: Int)
    case linearUp(inc: Double, unit: String)
    case greyskullDoubleJump(amrap: Int, inc: Double, unit: String)
    case linearDeload(stalls: Int, load: Double, unit: String)
    case linearHold(stallsRemaining: Int, deloadAt: Int)
    case custom(String)

    public func render() -> String {
        switch self {
        case .baseline:
            return "Nothing logged yet — this session sets the baseline."
        case .heldEverySet(let incSec):
            return "Held every set for the full time — target up by \(incSec)s."
        case .timeShortDeload(let stalls, let sec):
            return "Short \(stalls) sessions in a row — back off to \(sec)s and build up again."
        case .timeShortHold:
            return "Last time came up short — same target again."
        case .bwHoldClean:
            return "Bodyweight — same target again until every set is clean."
        case .bwAddSet(let goal, let bottom):
            return "\(goal) reps in every set — add a set and go back to \(bottom)."
        case .bwAddWeightOrHarder(let sets, let goal):
            return "\(sets) sets of \(goal) — time to add weight or move to a harder variation."
        case .bwMoreReps(let next):
            return "Bodyweight — every rep last time, so go for \(next) this time."
        case .doubleUp(let inc, let u, let bottom):
            return "Top of the rep range in every set — \(format(inc)) \(u) more, back to \(bottom) reps."
        case .doubleDeload(let stalls, let load, let u):
            return "Stalled \(stalls) sessions — deload to \(format(load)) \(u)."
        case .doubleHold(let aim):
            return "Same weight — aim for \(aim) reps this time."
        case .linearUp(let inc, let u):
            return "Every rep last time — \(format(inc)) \(u) more."
        case .greyskullDoubleJump(let amrap, let inc, let u):
            return "Last set hit \(amrap) reps — twice the target, so take a double jump of \(format(inc)) \(u)."
        case .linearDeload(let stalls, let load, let u):
            return stalls > 1
                ? "Missed reps \(stalls) sessions running — reset to \(format(load)) \(u) and work back up."
                : "Missed reps — reset to \(format(load)) \(u) and work back up."
        case .linearHold(let remaining, let total):
            return "Missed reps last time — same weight again (\(remaining) of \(total) to go)."
        case .custom(let str):
            return str
        }
    }

    private func format(_ v: Double) -> String {
        if v.rounded() == v {
            return String(format: "%.0f", v)
        }
        return String(format: "%.1f", v)
    }
}

public struct Prescription: Sendable, Equatable {
    public enum Kind: String, Sendable, Codable, Equatable {
        case first, up, hold, deload, off
    }

    public let policy: ProgressionPolicy
    public let kind: Kind
    public let weightKg: Double?
    public let reps: Int?
    public let sets: Int?
    public let sec: Int?
    public let why: WhyTemplate

    public init(
        policy: ProgressionPolicy,
        kind: Kind,
        weightKg: Double? = nil,
        reps: Int? = nil,
        sets: Int? = nil,
        sec: Int? = nil,
        why: WhyTemplate
    ) {
        self.policy = policy
        self.kind = kind
        self.weightKg = weightKg
        self.reps = reps
        self.sets = sets
        self.sec = sec
        self.why = why
    }
}

public enum ProgressionDirection: Sendable, Equatable {
    case increaseLoad
    case hold
    case decreaseLoad
    case addSet
}

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

public struct ProgressionRule: Sendable {
    public static let deloadAfter: [ProgressionPolicy: Int] = [
        .linear: 3,
        .greyskull: 1,
        .double: 3,
        .time: 3
    ]
    public static let deloadFactor = 0.9
    public static let maxBodyweightSets = 6

    private let maxIncreaseFraction: Double
    private let maxDecreaseFraction: Double
    /// Smallest loadable plate change in the profile's unit: 2.5 kg or 5 lb. Used by the
    /// legacy feel-based path's cap rounding so an `lb` profile doesn't snap to 2.5 lb.
    private let plateStep: Double

    public init(maxIncreaseFraction: Double = 0.10, maxDecreaseFraction: Double = 0.15, unit: MassUnit = .kg) {
        self.maxIncreaseFraction = maxIncreaseFraction
        self.maxDecreaseFraction = maxDecreaseFraction
        self.plateStep = unit == .lb ? 5.0 : 2.5
    }

    public static func defaultIncrement(bodyPart: String? = nil, unit: MassUnit = .kg) -> Double {
        let heavyBPs = ["upper legs", "lower legs", "back", "hips", "glutes", "quads", "hamstrings"]
        let isHeavy = bodyPart.map { heavyBPs.contains($0.lowercased()) } ?? false
        if unit == .lb {
            return isHeavy ? 10.0 : 5.0
        }
        return isHeavy ? 5.0 : 2.5
    }

    public static func snap(_ v: Double, step: Double) -> Double {
        guard step > 0 else { return (v * 10).rounded() / 10.0 }
        return ((v / step).rounded() * step * 10).rounded() / 10.0
    }

    public static func deloadTo(current: Double, step: Double) -> Double {
        var next = snap(current * deloadFactor, step: step)
        if next >= current {
            next = snap(current - step, step: step)
        }
        return max(step, next)
    }

    public func next(
        current: PrescriptionTarget,
        mechanic: Mechanic,
        history: [SessionReading],
        unit: MassUnit = .kg
    ) -> Prescription {
        // The history-based engine covers the openGym-style policies. `.standardLinear` is
        // the feel-based AI rule and carries no feel signal here, so it runs as plain
        // linear — use the legacy next(currentTargetLoadKg:...) entry point when feel
        // matters. `.deload` is handled explicitly in the weighted-reps path below.
        let rawPolicy = current.policy ?? .linear
        let policy: ProgressionPolicy = (rawPolicy == .standardLinear) ? .linear : rawPolicy
        if policy == .off {
            return Prescription(policy: .off, kind: .off, why: .custom("Manual progression only."))
        }

        let unitStr = unit == .lb ? "lb" : "kg"
        let inc = (current.incKg ?? 0) > 0 ? current.incKg! : (current.mode == .time ? 5.0 : Self.defaultIncrement(unit: unit))

        guard let last = history.last else {
            return Prescription(
                policy: policy,
                kind: .first,
                weightKg: current.loadKg,
                reps: current.reps,
                sets: current.sets,
                sec: current.sec,
                why: .baseline
            )
        }

        let stalls = SessionReadingReducer.stallCount(history)
        let deloadAt = Self.deloadAfter[policy] ?? 3

        if current.mode == .time {
            if last.ok {
                let sec = (last.goal > 0 ? last.goal : current.sec) + Int(inc)
                return Prescription(policy: policy, kind: .up, sec: sec, why: .heldEverySet(incSec: Int(inc)))
            }
            if stalls >= deloadAt {
                let curSec = Double(last.goal > 0 ? last.goal : current.sec)
                let sec = Int(Self.deloadTo(current: curSec, step: 5.0))
                return Prescription(policy: policy, kind: .deload, sec: sec, why: .timeShortDeload(stalls: stalls, sec: sec))
            }
            return Prescription(policy: policy, kind: .hold, sec: last.goal > 0 ? last.goal : current.sec, why: .timeShortHold)
        }

        let w = last.weightKg
        // Bodyweight branch (logged weight <= 0)
        if w <= 0 {
            let goal = last.goal > 0 ? last.goal : current.reps
            if !last.ok || goal <= 0 {
                return Prescription(policy: policy, kind: .hold, weightKg: 0, reps: goal > 0 ? goal : nil, why: .bwHoldClean)
            }
            let top = (current.repsMax ?? 0) > 0 ? current.repsMax! : 0
            if top > 0 && goal >= top {
                let currentSets = max(1, current.sets)
                let newSets = currentSets + 1
                let bottom = max(1, min(current.reps, top))
                if newSets <= Self.maxBodyweightSets {
                    return Prescription(policy: policy, kind: .up, weightKg: 0, reps: bottom, sets: newSets, why: .bwAddSet(goal: goal, bottom: bottom))
                }
                return Prescription(policy: policy, kind: .hold, weightKg: 0, reps: goal, sets: currentSets, why: .bwAddWeightOrHarder(sets: currentSets, goal: goal))
            }
            let step = current.perSide ? 2 : 1
            let nextReps = goal + step
            return Prescription(policy: policy, kind: .up, weightKg: 0, reps: nextReps, why: .bwMoreReps(next: nextReps))
        }

        if policy == .deload {
            let dw = Self.deloadTo(current: w, step: inc)
            return Prescription(
                policy: .deload, kind: .deload,
                weightKg: dw, reps: current.reps, sets: max(1, current.sets - 1),
                why: .custom("Planned deload — lighter load, one less set.")
            )
        }

        if policy == .double {
            let normalized = RepRangeNormalize.normalize(
                reps: last.goal > 0 ? last.goal : current.reps,
                repsMin: current.repsMin,
                stride: current.perSide ? 2 : 1
            )
            let top = normalized.reps
            let bottom = normalized.repsMin

            if last.ok {
                let newWeight = Self.snap(w + inc, step: inc)
                return Prescription(policy: policy, kind: .up, weightKg: newWeight, reps: bottom, why: .doubleUp(inc: inc, unit: unitStr, bottom: bottom))
            }
            if stalls >= deloadAt {
                let dw = Self.deloadTo(current: w, step: inc)
                return Prescription(policy: policy, kind: .deload, weightKg: dw, reps: bottom, why: .doubleDeload(stalls: stalls, load: dw, unit: unitStr))
            }
            let repStep = current.perSide ? 2 : 1
            let aim = min(top, max(bottom, last.low + repStep))
            return Prescription(policy: policy, kind: .hold, weightKg: w, reps: aim, why: .doubleHold(aim: aim))
        }

        // Linear + Greyskull
        if last.ok {
            let isGreyskullDbl = policy == .greyskull && last.goal > 0 && last.amrap >= last.goal * 2
            let step = isGreyskullDbl ? inc * 2 : inc
            let newWeight = Self.snap(w + step, step: inc)
            let why: WhyTemplate = isGreyskullDbl
                ? .greyskullDoubleJump(amrap: last.amrap, inc: step, unit: unitStr)
                : .linearUp(inc: step, unit: unitStr)
            return Prescription(policy: policy, kind: .up, weightKg: newWeight, why: why)
        }

        if stalls >= deloadAt {
            let dw = Self.deloadTo(current: w, step: inc)
            return Prescription(policy: policy, kind: .deload, weightKg: dw, why: .linearDeload(stalls: stalls, load: dw, unit: unitStr))
        }

        return Prescription(
            policy: policy,
            kind: .hold,
            weightKg: w,
            why: .linearHold(stallsRemaining: deloadAt - stalls, deloadAt: deloadAt)
        )
    }

    // MARK: - Legacy AI Coach Linear compatibility
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
            let newLoad = max(plateStep, roundToStep(currentTargetLoadKg * 0.90, step: plateStep))
            return ProgressionDecision(
                direction: .decreaseLoad,
                targetLoadKg: newLoad,
                targetSets: max(1, currentTargetSets - 1),
                targetReps: repRange,
                rationale: "planned deload — 10% load reduction and reduced volume"
            )

        case .double:
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

        case .greyskull:
            if let lastSet = working.last {
                if lastSet.actualReps >= repRange.max * 2 {
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
                    let newLoad = max(plateStep, roundToStep(currentTargetLoadKg * 0.90, step: plateStep))
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

        case .standardLinear, .linear, .off, .time:
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
        // `>=` (not `>`): at raw == ceiling, floor-to-step so a rounding step can never push
        // the result past the +max% cap.
        if raw >= ceiling {
            return (ceiling / plateStep).rounded(.down) * plateStep
        }
        return roundToStep(raw, step: plateStep)
    }

    private func cappedDecrease(from load: Double) -> Double {
        let raw = load * (1 - 0.05)
        let floor = load * (1 - maxDecreaseFraction)
        if raw <= floor {
            return (floor / plateStep).rounded(.up) * plateStep
        }
        return roundToStep(raw, step: plateStep)
    }

    private func roundToStep(_ value: Double, step: Double = 2.5) -> Double {
        (value / step).rounded() * step
    }
}
