import Foundation
import FitnessDomain
import Metrics

public enum SessionEntryBuilder {
    public struct BuiltEntry: Sendable, Equatable {
        public let exerciseID: String
        public let supersetID: String?
        public let target: PrescriptionTarget
        public let prescription: Prescription
        public let sets: [LoggedSetSnapshot]

        public init(
            exerciseID: String,
            supersetID: String? = nil,
            target: PrescriptionTarget,
            prescription: Prescription,
            sets: [LoggedSetSnapshot]
        ) {
            self.exerciseID = exerciseID
            self.supersetID = supersetID
            self.target = target
            self.prescription = prescription
            self.sets = sets
        }
    }

    public static func build(
        exerciseID: String,
        supersetID: String? = nil,
        target: PrescriptionTarget,
        mechanic: Mechanic = .compound,
        sessions: [CompletedSessionSnapshot],
        excludeFromProgression: Bool = false,
        unit: MassUnit = .kg
    ) -> BuiltEntry {
        if excludeFromProgression {
            let p = Prescription(policy: .off, kind: .off, why: .custom("Excluded from progression."))
            let sets = (0..<max(1, target.sets)).map { _ in
                LoggedSetSnapshot(
                    targetReps: target.reps,
                    targetLoadKg: target.loadKg,
                    actualReps: 0,
                    actualLoadKg: target.loadKg ?? 0,
                    startedAt: Date(),
                    completedAt: Date(),
                    restBeforeSec: 90
                )
            }
            return BuiltEntry(
                exerciseID: exerciseID,
                supersetID: supersetID,
                target: target,
                prescription: p,
                sets: sets
            )
        }

        let history = SessionReadingReducer.history(exerciseID: exerciseID, sessions: sessions, currentTarget: target)
        let prescription = ProgressionRule().next(current: target, mechanic: mechanic, history: history, unit: unit)

        let loadToUse = prescription.weightKg ?? target.loadKg ?? 0.0
        let repsToUse = prescription.reps ?? target.reps
        let setsCount = prescription.sets ?? target.sets

        let sets = (0..<max(1, setsCount)).map { _ in
            LoggedSetSnapshot(
                targetReps: repsToUse,
                targetLoadKg: loadToUse > 0 ? loadToUse : nil,
                actualReps: 0,
                actualLoadKg: loadToUse,
                startedAt: Date(),
                completedAt: Date(),
                restBeforeSec: 90
            )
        }

        return BuiltEntry(
            exerciseID: exerciseID,
            supersetID: supersetID,
            target: target,
            prescription: prescription,
            sets: sets
        )
    }
}
