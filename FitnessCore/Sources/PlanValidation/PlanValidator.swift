import FitnessDomain
import ExerciseCatalog
import RuleEngine

public enum ValidationIssue: Sendable, Equatable {
    case unknownExerciseID(String)
    case excludedExercisePresent(String)
    case excludedMusclePresent(MuscleGroup)
    case weeklyVolumeOutOfBand(muscle: MuscleGroup, actualSets: Int, band: VolumeBand)
    case emptySession(order: Int)
}

public struct PlanValidator: Sendable {
    private let catalog: CatalogStore

    public init(catalog: CatalogStore) {
        self.catalog = catalog
    }

    public func validate(_ plan: WeeklyPlan, context: UserContext) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        var flaggedExcludedMuscles: Set<MuscleGroup> = []

        let orderedSessions = plan.sessions.sorted { $0.order < $1.order }

        for session in orderedSessions {
            for item in session.items {
                let resolved = catalog.exercise(id: item.exerciseID)

                if resolved == nil {
                    issues.append(.unknownExerciseID(item.exerciseID))
                }
                if context.excludedExerciseIDs.contains(item.exerciseID) {
                    issues.append(.excludedExercisePresent(item.exerciseID))
                }
                if let muscle = resolved?.primaryMuscle,
                   context.excludedMuscles.contains(muscle),
                   !flaggedExcludedMuscles.contains(muscle) {
                    flaggedExcludedMuscles.insert(muscle)
                    issues.append(.excludedMusclePresent(muscle))
                }
            }
        }

        // Volume per resolvable primary muscle, summed across the plan.
        var setsByMuscle: [MuscleGroup: Int] = [:]
        for session in orderedSessions {
            for item in session.items {
                guard let muscle = catalog.exercise(id: item.exerciseID)?.primaryMuscle else { continue }
                setsByMuscle[muscle, default: 0] += item.targetSets
            }
        }
        for muscle in MuscleGroup.allCases {
            guard let actual = setsByMuscle[muscle] else { continue }
            let band = VolumeLandmarks.band(for: muscle, experience: context.experience)
            if actual < band.mev || actual > band.mrv {
                issues.append(.weeklyVolumeOutOfBand(muscle: muscle, actualSets: actual, band: band))
            }
        }

        for session in orderedSessions where session.items.isEmpty {
            issues.append(.emptySession(order: session.order))
        }

        return issues
    }
}
