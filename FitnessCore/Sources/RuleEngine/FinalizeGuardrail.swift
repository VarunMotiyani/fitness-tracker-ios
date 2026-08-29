import FitnessDomain
import ExerciseCatalog
import Metrics

/// A single way in which an AI-finalized session fell outside rule-engine-safe bounds.
public enum GuardrailViolation: Sendable, Equatable {
    case loadJumpTooLarge(exerciseID: String, proposedKg: Double, cappedKg: Double)
    case loadDropTooLarge(exerciseID: String, proposedKg: Double, cappedKg: Double)
    case weeklyVolumeOutOfBand(muscle: MuscleGroup, sets: Int, mev: Int, mrv: Int)
    case repTargetOutOfRange(exerciseID: String, target: RepRange, allowed: RepRange)
    case excludedExercise(exerciseID: String)
    case sessionTooLong(estimatedMin: Int, availableMin: Int)
}

/// The outcome of a `FinalizeGuardrail.check`: everything that was wrong, plus a
/// session in which every offending value has been snapped back to a safe one.
public struct GuardrailReport: Sendable, Equatable {
    public let violations: [GuardrailViolation]
    public let clampedSession: PlannedSession

    public init(violations: [GuardrailViolation], clampedSession: PlannedSession) {
        self.violations = violations
        self.clampedSession = clampedSession
    }
}

/// Sanity-checks an AI-finalized `PlannedSession` against rule-engine-safe bounds.
///
/// The check runs in a fixed order: exclusions first (offending items are dropped
/// before anything else looks at them), then per-surviving-item load and rep
/// checks, then the per-session volume proxy, then session length.
///
/// If no violation is found the returned `clampedSession` is identical to the
/// input.
public struct FinalizeGuardrail: Sendable {

    private let catalog: CatalogStore

    public init(catalog: CatalogStore) {
        self.catalog = catalog
    }

    private static let setSeconds = 40
    private static let lengthTolerance = 1.15
    private static let allowedReps = RepRange(min: 3, max: 20)

    public func check(
        finalized: PlannedSession,
        experience: ExperienceLevel,
        excludedExerciseIDs: Set<String>,
        excludedMuscles: Set<MuscleGroup>,
        availableEquipment: Set<Equipment>,
        lastPerformances: [String: ExercisePerformance],
        timeAvailableMin: Int,
        maxIncreaseFraction: Double = 0.10,
        maxDecreaseFraction: Double = 0.15
    ) -> GuardrailReport {
        var violations: [GuardrailViolation] = []

        // 1. Exclusions — drop offending items before any other rule runs.
        var items: [PlannedItem] = []
        for item in finalized.items {
            let exercise = catalog.exercise(id: item.exerciseID)
            let isExcluded =
                excludedExerciseIDs.contains(item.exerciseID)
                || exercise == nil
                || (exercise.map { excludedMuscles.contains($0.primaryMuscle) } ?? false)
                || (exercise.map { !availableEquipment.contains($0.equipment) } ?? false)
            if isExcluded {
                violations.append(.excludedExercise(exerciseID: item.exerciseID))
            } else {
                items.append(item)
            }
        }

        // 2. Load check — only when there is a prior performance and a proposed load.
        for index in items.indices {
            let item = items[index]
            guard let performance = lastPerformances[item.exerciseID],
                  let proposed = item.targetLoadKg,
                  let last = Self.bestWorkingLoad(performance) else { continue }
            let ceiling = last * (1 + maxIncreaseFraction)
            let floor = last * (1 - maxDecreaseFraction)
            if proposed > ceiling {
                // Round the ceiling DOWN so the capped load never breaches it.
                let capped = Self.floorToStep(ceiling)
                violations.append(.loadJumpTooLarge(exerciseID: item.exerciseID,
                                                    proposedKg: proposed, cappedKg: capped))
                items[index] = item.with(targetLoadKg: capped)
            } else if proposed < floor {
                // Round the floor UP so the capped load never breaches it.
                let capped = Self.ceilToStep(floor)
                violations.append(.loadDropTooLarge(exerciseID: item.exerciseID,
                                                    proposedKg: proposed, cappedKg: capped))
                items[index] = item.with(targetLoadKg: capped)
            }
        }

        // 3. Rep target envelope — universal RepRange(3...20) for Phase 2a.
        for index in items.indices {
            let item = items[index]
            guard item.targetReps.min < Self.allowedReps.min
                    || item.targetReps.max > Self.allowedReps.max else { continue }
            violations.append(.repTargetOutOfRange(exerciseID: item.exerciseID,
                                                   target: item.targetReps,
                                                   allowed: Self.allowedReps))
            let clamped = RepRange(min: max(Self.allowedReps.min, item.targetReps.min),
                                   max: min(Self.allowedReps.max, item.targetReps.max))
            items[index] = item.with(targetReps: clamped)
        }

        // 4. Weekly-volume proxy.
        //
        /// This sums `targetSets` per `primaryMuscle` across THIS session only and
        /// compares against the *weekly* volume landmarks. It is a coarse per-session
        /// proxy; the true cross-session weekly-volume check (summing every session in
        /// the training week) is the app's responsibility in Phase 2c.
        ///
        /// Only the above-weekly-MRV case mutates: a single session above the weekly
        /// MRV genuinely is too much, so its sets are scaled down. The below-weekly-MEV
        /// case is **report-only** — one session is *supposed* to sit below the weekly
        /// MEV, so `weeklyVolumeOutOfBand` is emitted for information but `targetSets`
        /// is left untouched.
        var setsByMuscle: [MuscleGroup: Int] = [:]
        var indicesByMuscle: [MuscleGroup: [Int]] = [:]
        for index in items.indices {
            guard let exercise = catalog.exercise(id: items[index].exerciseID) else { continue }
            setsByMuscle[exercise.primaryMuscle, default: 0] += items[index].targetSets
            indicesByMuscle[exercise.primaryMuscle, default: []].append(index)
        }
        for muscle in MuscleGroup.allCases {
            guard let total = setsByMuscle[muscle] else { continue }
            let band = VolumeLandmarks.band(for: muscle, experience: experience)
            if total > band.mrv {
                violations.append(.weeklyVolumeOutOfBand(muscle: muscle, sets: total,
                                                         mev: band.mev, mrv: band.mrv))
                for index in indicesByMuscle[muscle] ?? [] {
                    let original = Double(items[index].targetSets)
                    let scaled = max(1, Int((original * Double(band.mrv) / Double(total)).rounded()))
                    items[index] = items[index].with(targetSets: scaled)
                }
            } else if total < band.mev {
                // Report only — do not inflate a realistic single session.
                violations.append(.weeklyVolumeOutOfBand(muscle: muscle, sets: total,
                                                         mev: band.mev, mrv: band.mrv))
            }
        }

        // 5. Session length — trim whole trailing items until it fits (or one remains).
        let originalEstimate = Self.estimatedMinutes(items)
        let limit = Double(timeAvailableMin) * Self.lengthTolerance
        if originalEstimate > limit {
            violations.append(.sessionTooLong(estimatedMin: Int(originalEstimate.rounded()),
                                              availableMin: timeAvailableMin))
            while items.count > 1 && Self.estimatedMinutes(items) > limit {
                items.removeLast()
            }
        }

        let clampedSession = violations.isEmpty
            ? finalized
            : PlannedSession(id: finalized.id, order: finalized.order,
                             focusMuscles: finalized.focusMuscles, items: items)
        return GuardrailReport(violations: violations, clampedSession: clampedSession)
    }

    /// Max working-set `actualLoadKg` across the recorded sets, if any.
    private static func bestWorkingLoad(_ performance: ExercisePerformance) -> Double? {
        performance.sets.filter { $0.isWorkingSet }.map(\.actualLoadKg).max()
    }

    private static func floorToStep(_ value: Double) -> Double { (value / 2.5).rounded(.down) * 2.5 }
    private static func ceilToStep(_ value: Double) -> Double { (value / 2.5).rounded(.up) * 2.5 }

    private static func estimatedMinutes(_ items: [PlannedItem]) -> Double {
        items.reduce(0.0) { partial, item in
            partial + Double(item.targetSets) * Double(setSeconds + item.restSeconds)
        } / 60.0
    }
}

private extension PlannedItem {
    /// Rebuild with selected fields replaced (all of `PlannedItem`'s fields are `let`).
    func with(targetSets: Int? = nil,
              targetReps: RepRange? = nil,
              targetLoadKg: Double?? = nil) -> PlannedItem {
        PlannedItem(exerciseID: exerciseID,
                    targetSets: targetSets ?? self.targetSets,
                    targetReps: targetReps ?? self.targetReps,
                    targetLoadKg: targetLoadKg ?? self.targetLoadKg,
                    restSeconds: restSeconds,
                    coachNote: coachNote)
    }
}
