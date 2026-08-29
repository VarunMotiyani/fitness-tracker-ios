import Foundation
import FitnessDomain
import ExerciseCatalog

/// Weekly count of working sets attributed to a single muscle group.
public struct WeeklyMuscleVolume: Sendable, Codable, Equatable {
    public let weekStart: Date
    public let muscle: MuscleGroup
    public let sets: Int

    public init(weekStart: Date, muscle: MuscleGroup, sets: Int) {
        self.weekStart = weekStart
        self.muscle = muscle
        self.sets = sets
    }
}

/// One data point in an exercise's strength trend, derived from a single session.
public struct ExerciseTrendPoint: Sendable, Codable, Equatable {
    public let exerciseID: String
    public let date: Date
    public let e1RM: Double
    public let bestSetLoadKg: Double
    public let bestSetReps: Int
    public let tonnage: Double

    public init(exerciseID: String, date: Date, e1RM: Double,
                bestSetLoadKg: Double, bestSetReps: Int, tonnage: Double) {
        self.exerciseID = exerciseID
        self.date = date
        self.e1RM = e1RM
        self.bestSetLoadKg = bestSetLoadKg
        self.bestSetReps = bestSetReps
        self.tonnage = tonnage
    }
}

/// Derives weekly muscle volume and per-exercise trend points from completed sessions.
public struct RollupComputer: Sendable {
    private let catalog: CatalogStore

    public init(catalog: CatalogStore) {
        self.catalog = catalog
    }

    /// Counts each working set as 1 toward its exercise's `primaryMuscle`, bucketed
    /// by the week containing the session's date per the supplied `Calendar`
    /// (default: ISO-8601, UTC). Sets whose exercise id is unknown to the catalog
    /// are skipped.
    /// Output is sorted by `(weekStart ascending, MuscleGroup.allCases order)`.
    public func weeklyMuscleVolume(from sessions: [CompletedSessionSnapshot],
                                   calendar: Calendar = .isoUTC) -> [WeeklyMuscleVolume] {
        var counts: [Date: [MuscleGroup: Int]] = [:]

        for session in sessions {
            guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: session.date)?.start else {
                continue
            }
            for entry in session.entries where entry.countsTowardMetrics {
                guard let exercise = catalog.exercise(id: entry.exerciseID) else { continue }
                let muscle = exercise.primaryMuscle
                for set in entry.sets where set.isWorkingSet {
                    counts[weekStart, default: [:]][muscle, default: 0] += 1
                }
            }
        }

        var result: [WeeklyMuscleVolume] = []
        for weekStart in counts.keys.sorted() {
            let muscleCounts = counts[weekStart] ?? [:]
            for muscle in MuscleGroup.allCases {
                guard let n = muscleCounts[muscle] else { continue }
                result.append(WeeklyMuscleVolume(weekStart: weekStart, muscle: muscle, sets: n))
            }
        }
        return result
    }

    /// One point per session containing at least one working set for `exerciseID`.
    /// `e1RM` is the max Epley estimate over the working sets; `bestSetLoadKg` /
    /// `bestSetReps` come from the set with the highest Epley estimate; `tonnage`
    /// is Σ `actualReps * actualLoadKg` over the working sets. e1RM ties resolve
    /// to the first working set seen (strict `>` comparison).
    /// Output is sorted by `date` ascending.
    public func exerciseTrend(from sessions: [CompletedSessionSnapshot],
                              exerciseID: String) -> [ExerciseTrendPoint] {
        var points: [ExerciseTrendPoint] = []

        for session in sessions {
            let workingSets = session.entries
                .filter { $0.exerciseID == exerciseID && $0.countsTowardMetrics }
                .flatMap { $0.sets }
                .filter { $0.isWorkingSet }
            guard !workingSets.isEmpty else { continue }

            var bestE1RM = -1.0
            var bestLoadKg = 0.0
            var bestReps = 0
            var tonnage = 0.0

            for set in workingSets {
                let estimate = Estimated1RM.epley(loadKg: set.actualLoadKg, reps: set.actualReps)
                if estimate > bestE1RM {
                    bestE1RM = estimate
                    bestLoadKg = set.actualLoadKg
                    bestReps = set.actualReps
                }
                tonnage += Double(set.actualReps) * set.actualLoadKg
            }

            points.append(ExerciseTrendPoint(exerciseID: exerciseID, date: session.date,
                                             e1RM: bestE1RM, bestSetLoadKg: bestLoadKg,
                                             bestSetReps: bestReps, tonnage: tonnage))
        }

        return points.sorted { $0.date < $1.date }
    }
}
