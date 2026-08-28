import Foundation

/// Detects new personal records produced by a completed session, given the
/// records that were already established before it.
public struct PRDetector: Sendable {
    public init() {}

    public func newPRs(in session: CompletedSessionSnapshot, priorPRs: [PersonalRecord]) -> [PersonalRecord] {
        var results: [PersonalRecord] = []

        // Gather working sets (isWarmup == false) grouped by exercise, in the
        // order the exercises first appear in the session.
        var setsByExercise: [String: [LoggedSetSnapshot]] = [:]
        var orderedExerciseIDs: [String] = []
        for entry in session.entries {
            let working = entry.sets.filter { $0.isWarmup == false }
            guard working.isEmpty == false else { continue }
            if setsByExercise[entry.exerciseID] == nil {
                orderedExerciseIDs.append(entry.exerciseID)
            }
            setsByExercise[entry.exerciseID, default: []].append(contentsOf: working)
        }

        for exerciseID in orderedExerciseIDs {
            guard let sets = setsByExercise[exerciseID], sets.isEmpty == false else { continue }

            // MARK: heaviestWeight
            let maxLoad = sets.map(\.actualLoadKg).max()!
            let repsAtMaxLoad = sets
                .filter { $0.actualLoadKg == maxLoad }
                .map(\.actualReps)
                .max()!
            let priorHeaviest = priorPRs
                .filter { $0.type == .heaviestWeight && $0.exerciseID == exerciseID }
                .map(\.value)
                .max()
            if priorHeaviest == nil || maxLoad > priorHeaviest! {
                results.append(PersonalRecord(
                    type: .heaviestWeight,
                    exerciseID: exerciseID,
                    value: maxLoad,
                    atLoadKg: maxLoad,
                    reps: repsAtMaxLoad,
                    date: session.date,
                    sessionID: session.id
                ))
            }

            // MARK: estimated1RM
            var bestE1RM = -1.0
            var bestE1RMSet = sets[0]
            for s in sets {
                let e = Estimated1RM.epley(loadKg: s.actualLoadKg, reps: s.actualReps)
                if e > bestE1RM {
                    bestE1RM = e
                    bestE1RMSet = s
                }
            }
            let priorE1RM = priorPRs
                .filter { $0.type == .estimated1RM && $0.exerciseID == exerciseID }
                .map(\.value)
                .max()
            if priorE1RM == nil || bestE1RM > priorE1RM! {
                results.append(PersonalRecord(
                    type: .estimated1RM,
                    exerciseID: exerciseID,
                    value: bestE1RM,
                    atLoadKg: bestE1RMSet.actualLoadKg,
                    reps: bestE1RMSet.actualReps,
                    date: session.date,
                    sessionID: session.id
                ))
            }

            // MARK: repsAtWeight
            let priorRAW = priorPRs.filter { $0.type == .repsAtWeight && $0.exerciseID == exerciseID }
            if priorRAW.isEmpty {
                // No established record yet: seed one from the best working set
                // (heaviest load, then most reps). The app decides toast-worthiness.
                let bestSet = sets.sorted { lhs, rhs in
                    lhs.actualLoadKg != rhs.actualLoadKg
                        ? lhs.actualLoadKg > rhs.actualLoadKg
                        : lhs.actualReps > rhs.actualReps
                }.first!
                results.append(PersonalRecord(
                    type: .repsAtWeight,
                    exerciseID: exerciseID,
                    value: Double(bestSet.actualReps),
                    atLoadKg: bestSet.actualLoadKg,
                    reps: bestSet.actualReps,
                    date: session.date,
                    sessionID: session.id
                ))
            } else {
                // Compare against the heaviest load the user has an established
                // repsAtWeight record at.
                let heaviestPriorLoad = priorRAW.map(\.atLoadKg).max()!
                let priorReps = priorRAW
                    .filter { $0.atLoadKg == heaviestPriorLoad }
                    .map(\.reps)
                    .max()!
                let repsThisSession = sets
                    .filter { $0.actualLoadKg == heaviestPriorLoad }
                    .map(\.actualReps)
                    .max()
                if let r = repsThisSession, r > priorReps {
                    results.append(PersonalRecord(
                        type: .repsAtWeight,
                        exerciseID: exerciseID,
                        value: Double(r),
                        atLoadKg: heaviestPriorLoad,
                        reps: r,
                        date: session.date,
                        sessionID: session.id
                    ))
                }
            }
        }

        return results
    }
}
