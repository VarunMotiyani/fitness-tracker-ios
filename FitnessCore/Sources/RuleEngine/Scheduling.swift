import Foundation
import FitnessDomain

public enum Scheduling {
    public static func isoDateKey(_ date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        let d = comps.day ?? 0
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// The routine that applies on `date`: a `dayPlan[iso]` override ("rest" -> nil, or a
    /// routine id) wins; otherwise the weekday's assigned routine from `week`.
    public static func effectiveRoutineID(
        week: [Int: String],
        dayPlan: [String: String],
        date: Date,
        calendar: Calendar = .current
    ) -> String? {
        let iso = isoDateKey(date, calendar: calendar)
        if let override = dayPlan[iso] {
            if override.lowercased() == "rest" {
                return nil
            }
            return override
        }
        let weekday = calendar.component(.weekday, from: date)
        return week[weekday]
    }

    /// The next date on/after `from` that has a non-rest effective routine (scans up to 14 days).
    public static func nextTrainingDay(
        week: [Int: String],
        dayPlan: [String: String],
        from: Date,
        calendar: Calendar = .current,
        scanDays: Int = 14
    ) -> (date: Date, routineID: String)? {
        for offset in 0..<scanDays {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: from) else { continue }
            if let routineID = effectiveRoutineID(week: week, dayPlan: dayPlan, date: candidate, calendar: calendar) {
                return (date: candidate, routineID: routineID)
            }
        }
        return nil
    }

    /// Result of `autoRescheduleMissedSessions`.
    public struct MissedSessionReschedule: Sendable, Equatable {
        /// `dayPlan` with catch-up overrides applied: every missed slot set to
        /// `"rest"`, and — where a free day existed — its routine written onto
        /// the new date. A superset of the input `dayPlan`.
        public var dayPlan: [String: String]
        /// Missed sessions that could NOT be placed on any free day left in the
        /// week. The caller must surface these (a coach reaction), never drop
        /// them — the whole point is that an N-day plan still owes N sessions.
        public var unplaced: [Unplaced]

        public struct Unplaced: Sendable, Equatable {
            /// ISO day the session was originally due.
            public let originalDateKey: String
            /// Routine that was due (recurring id, or a prior catch-up's id).
            public let routineID: String
            public init(originalDateKey: String, routineID: String) {
                self.originalDateKey = originalDateKey
                self.routineID = routineID
            }
        }

        public init(dayPlan: [String: String], unplaced: [Unplaced]) {
            self.dayPlan = dayPlan
            self.unplaced = unplaced
        }
    }

    /// Moves every scheduled session that elapsed without a completed workout to
    /// the earliest free day left in the same Monday–Sunday week — chronological
    /// order, one session per day (never doubled up). Sunday is a valid target.
    /// A catch-up day that is itself missed on a later run is chased again.
    ///
    /// `"rest"` overrides and any day the athlete has already trained are left
    /// untouched. Sessions with no free day remaining this week come back in
    /// `unplaced` rather than being silently lost.
    /// - Parameter conflictsOnAdjacentDay: `true` when two routines shouldn't sit
    ///   on back-to-back days (e.g. they hit the same muscle group). A catch-up
    ///   day whose neighbour already runs a conflicting routine is skipped in
    ///   favour of a later free day; if every free day conflicts, the earliest
    ///   is still used — a same-muscle adjacency beats a dropped session.
    ///   Defaults to "same routine id conflicts".
    public static func autoRescheduleMissedSessions(
        week: [Int: String],
        dayPlan: [String: String],
        completedDates: Set<String>,
        through: Date,
        calendar: Calendar = .current,
        conflictsOnAdjacentDay: (_ routineA: String, _ routineB: String) -> Bool = { $0 == $1 }
    ) -> MissedSessionReschedule {
        let today = calendar.startOfDay(for: through)
        let todayWeekday = calendar.component(.weekday, from: today)
        // Calendar weekday values are Sunday=1 ... Saturday=7. Keep the
        // product's Monday-first week regardless of the user's locale.
        let daysFromMonday = (todayWeekday + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: today) else {
            return MissedSessionReschedule(dayPlan: dayPlan, unplaced: [])
        }

        let weekDays: [(date: Date, key: String, weekday: Int)] = (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: monday) else { return nil }
            return (date, isoDateKey(date, calendar: calendar), calendar.component(.weekday, from: date))
        }

        var overrides = dayPlan

        // The routine due on a slot: a non-rest date override wins over the
        // recurring weekday assignment; a "rest" override means nothing is due.
        func dueRoutine(on key: String, weekday: Int) -> String? {
            if let override = overrides[key] {
                return override.lowercased() == "rest" ? nil : override
            }
            guard let recurring = week[weekday], !recurring.isEmpty else { return nil }
            return recurring
        }

        let missed: [(key: String, routineID: String)] = weekDays.compactMap { day in
            guard day.date < today,
                  !completedDates.contains(day.key),
                  let routineID = dueRoutine(on: day.key, weekday: day.weekday)
            else { return nil }
            return (day.key, routineID)
        }

        var openDays = weekDays.filter { day in
            day.date >= today &&
            !completedDates.contains(day.key) &&
            overrides[day.key] == nil &&
            week[day.weekday] == nil
        }

        // Whether placing `routineID` on `day` would sit it next to a
        // conflicting routine (reads `overrides` as it's being built, so a
        // catch-up placed earlier in this loop counts).
        func adjacentClash(_ routineID: String, _ day: (date: Date, key: String, weekday: Int)) -> Bool {
            guard let i = weekDays.firstIndex(where: { $0.key == day.key }) else { return false }
            let neighbours = [i - 1, i + 1].filter { weekDays.indices.contains($0) }.map { weekDays[$0] }
            return neighbours.contains { n in
                guard let r = dueRoutine(on: n.key, weekday: n.weekday) else { return false }
                return conflictsOnAdjacentDay(routineID, r)
            }
        }

        var unplaced: [MissedSessionReschedule.Unplaced] = []
        for session in missed {
            overrides[session.key] = "rest" // vacate the missed slot
            let pick = openDays.firstIndex { !adjacentClash(session.routineID, $0) }
                ?? (openDays.isEmpty ? nil : openDays.startIndex)
            if let pick {
                overrides[openDays.remove(at: pick).key] = session.routineID
            } else {
                unplaced.append(.init(originalDateKey: session.key, routineID: session.routineID))
            }
        }

        return MissedSessionReschedule(dayPlan: overrides, unplaced: unplaced)
    }
}
