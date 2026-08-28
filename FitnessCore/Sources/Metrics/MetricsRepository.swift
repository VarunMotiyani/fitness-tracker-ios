import Foundation
import FitnessDomain
import ExerciseCatalog

/// The most recent logged performance of a single exercise.
public struct ExercisePerformance: Sendable, Equatable {
    public let exerciseID: String
    public let date: Date
    public let sets: [LoggedSetSnapshot]
    public let feel: Feel?

    public init(exerciseID: String, date: Date, sets: [LoggedSetSnapshot], feel: Feel?) {
        self.exerciseID = exerciseID
        self.date = date
        self.sets = sets
        self.feel = feel
    }
}

/// The single typed query surface over all recorded training metrics.
public protocol MetricsRepository: Sendable {
    /// Most recent session containing `exerciseID`, with that entry's sets and feel.
    func lastPerformance(exerciseID: String) -> ExercisePerformance?

    /// Working set with the highest Epley estimated 1RM for `exerciseID`,
    /// optionally restricted to sessions on or after `since`.
    func bestSet(exerciseID: String, since: Date?) -> LoggedSetSnapshot?

    /// One trend point per session containing a working set for `exerciseID`,
    /// ascending by date, optionally restricted to `since`.
    func e1RMSeries(exerciseID: String, since: Date?) -> [ExerciseTrendPoint]

    /// Weekly working-set counts for `muscle` over the trailing `weeks` window
    /// ending at `now`.
    func weeklyVolume(muscle: MuscleGroup, weeks: Int, now: Date) -> [WeeklyMuscleVolume]

    /// All detected personal records, optionally filtered to a single exercise.
    func personalRecords(exerciseID: String?) -> [PersonalRecord]

    /// Completed-or-partial sessions in the trailing `weeks` window ending at
    /// `now`, divided by planned session slots, clamped to `0...1`.
    func adherence(weeks: Int, now: Date) -> Double

    /// Exercise ids whose last three trend points show no e1RM increase.
    func stalls() -> [String]

    /// Observations of `kind`, optionally restricted to on/after `since`.
    func observations(kind: String, since: Date?) -> [ObservationSnapshot]
}

/// Pure in-memory `MetricsRepository` over fixed snapshot arrays.
public struct InMemoryMetricsRepository: MetricsRepository {
    private let sessions: [CompletedSessionSnapshot]
    private let allObservations: [ObservationSnapshot]
    private let plannedSessionsPerWeek: Int
    private let calendar: Calendar
    private let rollups: RollupComputer
    private let prs: [PersonalRecord]

    public init(sessions: [CompletedSessionSnapshot],
                priorPRs: [PersonalRecord],
                observations: [ObservationSnapshot],
                plannedSessionsPerWeek: Int,
                catalog: CatalogStore,
                calendar: Calendar = .init(identifier: .gregorian)) {
        let ordered = sessions.sorted { $0.date < $1.date }
        self.sessions = ordered
        self.allObservations = observations
        self.plannedSessionsPerWeek = plannedSessionsPerWeek
        self.calendar = calendar
        self.rollups = RollupComputer(catalog: catalog)

        let detector = PRDetector()
        var accumulated = priorPRs
        for session in ordered {
            accumulated.append(contentsOf: detector.newPRs(in: session, priorPRs: accumulated))
        }
        self.prs = accumulated
    }

    public func lastPerformance(exerciseID: String) -> ExercisePerformance? {
        for session in sessions.reversed() {
            guard let entry = session.entries.first(where: { $0.exerciseID == exerciseID }) else { continue }
            return ExercisePerformance(exerciseID: exerciseID, date: session.date,
                                       sets: entry.sets, feel: entry.feel)
        }
        return nil
    }

    public func bestSet(exerciseID: String, since: Date?) -> LoggedSetSnapshot? {
        let working = sessions
            .filter { since == nil || $0.date >= since! }
            .flatMap(\.entries)
            .filter { $0.exerciseID == exerciseID }
            .flatMap(\.sets)
            .filter { !$0.isWarmup }
        return working.max { lhs, rhs in
            Estimated1RM.epley(loadKg: lhs.actualLoadKg, reps: lhs.actualReps)
                < Estimated1RM.epley(loadKg: rhs.actualLoadKg, reps: rhs.actualReps)
        }
    }

    public func e1RMSeries(exerciseID: String, since: Date?) -> [ExerciseTrendPoint] {
        let points = rollups.exerciseTrend(from: sessions, exerciseID: exerciseID)
        guard let since else { return points }
        return points.filter { $0.date >= since }
    }

    public func weeklyVolume(muscle: MuscleGroup, weeks: Int, now: Date) -> [WeeklyMuscleVolume] {
        guard weeks > 0, let windowStart = calendar.date(byAdding: .day, value: -weeks * 7, to: now) else {
            return []
        }
        let windowed = sessions.filter { $0.date >= windowStart && $0.date <= now }
        return rollups.weeklyMuscleVolume(from: windowed, calendar: calendar)
            .filter { $0.muscle == muscle }
    }

    public func personalRecords(exerciseID: String?) -> [PersonalRecord] {
        guard let exerciseID else { return prs }
        return prs.filter { $0.exerciseID == exerciseID }
    }

    public func adherence(weeks: Int, now: Date) -> Double {
        guard weeks > 0, plannedSessionsPerWeek > 0,
              let windowStart = calendar.date(byAdding: .day, value: -weeks * 7, to: now) else {
            return 0
        }
        let count = sessions.filter {
            $0.date >= windowStart && $0.date <= now
                && ($0.outcome == .complete || $0.outcome == .partial)
        }.count
        let raw = Double(count) / Double(weeks * plannedSessionsPerWeek)
        return min(1, max(0, raw))
    }

    public func stalls() -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for session in sessions {
            for entry in session.entries where !seen.contains(entry.exerciseID) {
                seen.insert(entry.exerciseID)
                ordered.append(entry.exerciseID)
            }
        }
        return ordered.filter { id in
            let trend = rollups.exerciseTrend(from: sessions, exerciseID: id)
            guard trend.count >= 3, let last = trend.last else { return false }
            return last.e1RM <= trend[trend.count - 3].e1RM
        }
    }

    public func observations(kind: String, since: Date?) -> [ObservationSnapshot] {
        allObservations.filter {
            $0.kind == kind && (since == nil || $0.timestamp >= since!)
        }
    }
}
