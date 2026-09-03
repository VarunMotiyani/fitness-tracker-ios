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
        weekStart: WeekStart = .monday,
        calendar: Calendar = .isoUTC
    ) -> Summary {
        var cal = calendar
        cal.firstWeekday = (weekStart == .sunday) ? 1 : 2

        let validSessions = sessions.filter { $0.entries.contains { $0.countsTowardMetrics } }
        let totalCount = validSessions.count
        guard totalCount > 0 else {
            return Summary(currentStreakWeeks: 0, workoutsThisWeek: 0, plannedPerWeek: plannedPerWeek, totalWorkouts: 0)
        }

        // Build set of week keys
        var trainedWeeks = Set<String>()
        for s in validSessions {
            let k = WeekKey.key(s.date, weekStart: weekStart, calendar: cal)
            trainedWeeks.insert(k)
        }

        // Current week info
        let currentWeekKey = WeekKey.key(now, weekStart: weekStart, calendar: cal)
        let currentWeekStart = WeekKey.startOfWeek(now, weekStart: weekStart, calendar: cal)

        let thisWeekCount = validSessions.filter { s in
            WeekKey.key(s.date, weekStart: weekStart, calendar: cal) == currentWeekKey
        }.count

        // Streak counting
        var streak = 0
        var cursor = currentWeekStart

        for i in 0..<520 { // up to 10 years
            let key = WeekKey.key(cursor, weekStart: weekStart, calendar: cal)
            let isTrained = trainedWeeks.contains(key)

            if i == 0 {
                // Current week: if trained, streak = 1; if not, streak can still continue from last week
                if isTrained {
                    streak += 1
                }
            } else {
                if isTrained {
                    streak += 1
                } else {
                    break
                }
            }

            // Move back one calendar week. `.weekOfYear` (not −7 days) so the cursor stays
            // on a week boundary even if a non-UTC calendar with DST is passed in.
            guard let prev = cal.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
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
