import Foundation
import FitnessDomain

/// Computes consecutive weekly workout streaks and microcycle adherence matching openGym.
public struct StreakCalculator: Sendable {

    public struct Summary: Sendable, Codable, Equatable {
        public let currentStreakWeeks: Int
        public let workoutsThisWeek: Int
        public let plannedPerWeek: Int
        public let totalWorkouts: Int

        public init(currentStreakWeeks: Int, workoutsThisWeek: Int, plannedPerWeek: Int, totalWorkouts: Int) {
            self.currentStreakWeeks = currentStreakWeeks
            self.workoutsThisWeek = workoutsThisWeek
            self.plannedPerWeek = plannedPerWeek
            self.totalWorkouts = totalWorkouts
        }
    }

    /// Computes consecutive training weeks from completed sessions.
    public static func computeSummary(
        from sessions: [CompletedSessionSnapshot],
        plannedPerWeek: Int,
        now: Date = .now,
        calendar: Calendar = .isoUTC
    ) -> Summary {
        let validSessions = sessions.filter { $0.entries.contains { $0.countsTowardMetrics } }
        let totalCount = validSessions.count
        guard totalCount > 0 else {
            return Summary(currentStreakWeeks: 0, workoutsThisWeek: 0, plannedPerWeek: plannedPerWeek, totalWorkouts: 0)
        }

        // Build set of week keys
        var trainedWeeks = Set<String>()
        for s in validSessions {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: s.date)?.start else { continue }
            let yr = calendar.component(.yearForWeekOfYear, from: start)
            let wk = calendar.component(.weekOfYear, from: start)
            trainedWeeks.insert("\(yr)-W\(wk)")
        }

        // Current week info
        guard let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else {
            return Summary(currentStreakWeeks: 0, workoutsThisWeek: 0, plannedPerWeek: plannedPerWeek, totalWorkouts: totalCount)
        }

        let thisWeekCount = validSessions.filter { s in
            guard let sStart = calendar.dateInterval(of: .weekOfYear, for: s.date)?.start else { return false }
            return calendar.isDate(sStart, equalTo: currentWeekStart, toGranularity: .day)
        }.count

        // Streak counting
        var streak = 0
        var cursor = currentWeekStart

        for i in 0..<520 { // up to 10 years
            let yr = calendar.component(.yearForWeekOfYear, from: cursor)
            let wk = calendar.component(.weekOfYear, from: cursor)
            let key = "\(yr)-W\(wk)"

            if trainedWeeks.contains(key) {
                streak += 1
            } else if i > 0 {
                // Gap in past weeks breaks the streak
                break
            }
            guard let prev = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = prev
        }

        return Summary(
            currentStreakWeeks: streak,
            workoutsThisWeek: thisWeekCount,
            plannedPerWeek: plannedPerWeek,
            totalWorkouts: totalCount
        )
    }
}
