import Foundation
import FitnessDomain
import RuleEngine
import Metrics

/// The app-wide source of truth for recurring workout slots and date overrides.
///
/// `PlanView` stores weekdays as Monday-first indices (0...6), while the Core
/// scheduling engine uses Foundation weekday values (Sunday=1...Saturday=7).
/// Keeping that translation here prevents each screen and AI consumer from
/// silently inventing a different schedule.
enum WorkoutScheduleStore {
    static let scheduleKey = "gym_week_schedule_json"
    /// The athlete's own date overrides (from the day sheet). Never written by
    /// the auto-reschedule.
    static let dayPlanKey = "gym_day_plan_json"
    /// The auto-reschedule's output, recomputed from scratch on every `refresh`.
    /// Kept separate so a session completed on its original day doesn't leave a
    /// stale catch-up baked into the user's plan (which double-counted the week).
    static let autoPlanKey = "gym_day_plan_auto_json"
    static let calendar = Calendar.appWeek

    static var weekSchedule: [Int: UUID] {
        decode([Int: UUID].self, key: scheduleKey) ?? [:]
    }

    /// The athlete's own overrides only.
    static var userDayPlan: [String: String] {
        decode([String: String].self, key: dayPlanKey) ?? [:]
    }

    /// The current auto-reschedule projection only.
    static var autoDayPlan: [String: String] {
        decode([String: String].self, key: autoPlanKey) ?? [:]
    }

    /// What every screen reads: the athlete's overrides with the auto-reschedule
    /// layered on top.
    static var dayPlan: [String: String] {
        userDayPlan.merging(autoDayPlan) { _, auto in auto }
    }

    static func saveWeekSchedule(_ schedule: [Int: UUID]) {
        encode(schedule, key: scheduleKey)
    }

    /// Persists an athlete override edit. Callers pass a mutated copy of
    /// `userDayPlan` (not `dayPlan`) so auto entries never leak into it.
    static func saveDayPlan(_ plan: [String: String]) {
        encode(plan, key: dayPlanKey)
    }

    /// Recomputes the auto-reschedule from the athlete's plan + current
    /// completions — fully idempotent, safe on every foreground and after a
    /// workout finishes. `unplaced` is the missed sessions the week has no room
    /// left for; the proactive coach reacts to those, they are never dropped.
    @discardableResult
    static func refresh(completedSessions: [CompletedSessionModel],
                        plan: WeeklyPlan? = nil,
                        now: Date = .now) -> Scheduling.MissedSessionReschedule {
        let user = userDayPlan
        let completedDates: Set<String> = Set(completedSessions.compactMap { session in
            guard session.finishedAt != nil else { return nil }
            return Scheduling.isoDateKey(session.startedAt, calendar: calendar)
        })
        let focus = plan.map(routineFocus)
        let result = Scheduling.autoRescheduleMissedSessions(
            week: foundationWeek,
            dayPlan: user,
            completedDates: completedDates,
            through: now,
            calendar: calendar,
            conflictsOnAdjacentDay: { a, b in
                guard a != b else { return true }
                guard let fa = focus?[a], let fb = focus?[b], !fa.isEmpty, !fb.isEmpty else { return false }
                return !fa.isDisjoint(with: fb)
            }
        )
        // Persist only the delta the auto-reschedule adds on top of the user plan.
        let auto = result.dayPlan.filter { user[$0.key] != $0.value }
        if auto != autoDayPlan { encode(auto, key: autoPlanKey) }
        return result
    }

    /// routineID → the muscle groups its session focuses, so the reschedule can
    /// avoid stacking overlapping work on consecutive days.
    private static func routineFocus(_ plan: WeeklyPlan) -> [String: Set<MuscleGroup>] {
        let ordered = plan.sessions.sorted { $0.order < $1.order }
        let routineOrder = weekSchedule.keys.sorted().compactMap { weekSchedule[$0] }
        var map: [String: Set<MuscleGroup>] = [:]
        for (i, routineID) in routineOrder.enumerated() where ordered.indices.contains(i) {
            map[routineID.uuidString] = Set(ordered[i].focusMuscles)
        }
        return map
    }

    static func effectiveRoutineID(for date: Date, dayPlan overrides: [String: String]? = nil) -> UUID? {
        let ids = overrides ?? dayPlan
        guard let raw = Scheduling.effectiveRoutineID(
            week: foundationWeek,
            dayPlan: ids,
            date: date,
            calendar: calendar
        ) else { return nil }
        return UUID(uuidString: raw)
    }

    /// A day is a rescheduled catch-up iff the auto layer placed a routine on
    /// it — precise, unlike inferring it from "a routine override on a rest
    /// weekday" (which an explicit athlete choice also looks like).
    static func isRescheduled(for date: Date) -> Bool {
        guard let auto = autoDayPlan[Scheduling.isoDateKey(date, calendar: calendar)] else { return false }
        return auto.lowercased() != "rest"
    }

    /// Maps the effective routine to the generated plan's stable session
    /// ordering. WeeklyPlan session IDs are distinct from the user-editable
    /// routine IDs, so recurring routine position is the only durable mapping.
    static func plannedSession(for date: Date, in plan: WeeklyPlan, dayPlan overrides: [String: String]? = nil) -> PlannedSession? {
        let ordered = plan.sessions.sorted { $0.order < $1.order }
        guard !ordered.isEmpty else { return nil }
        let key = Scheduling.isoDateKey(date, calendar: calendar)
        if let explicit = (overrides ?? dayPlan)[key],
           let direct = ordered.first(where: { $0.id.uuidString.caseInsensitiveCompare(explicit) == .orderedSame }) {
            return direct
        }
        guard !weekSchedule.isEmpty else { return ordered.first }
        guard let routineID = effectiveRoutineID(for: date, dayPlan: overrides) else { return nil }
        let routineOrder = weekSchedule.keys.sorted().compactMap { weekSchedule[$0] }
        let index = routineOrder.firstIndex(of: routineID) ?? 0
        return ordered.indices.contains(index) ? ordered[index] : ordered.first
    }

    static func routineID(for session: PlannedSession, in plan: WeeklyPlan) -> String {
        let ordered = plan.sessions.sorted { $0.order < $1.order }
        if let index = ordered.firstIndex(where: { $0.id == session.id }),
           let routine = weekSchedule.keys.sorted().compactMap({ weekSchedule[$0] })[safe: index] {
            return routine.uuidString
        }
        return session.id.uuidString
    }

    static func mondayFirstIndex(for date: Date) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    static func scheduleDescription(for date: Date = .now) -> String {
        let key = Scheduling.isoDateKey(date, calendar: calendar)
        let state = effectiveRoutineID(for: date) == nil ? "rest" : (isRescheduled(for: date) ? "rescheduled" : "scheduled")
        return "\(key): \(state); recurring weekdays \(weekSchedule.keys.sorted().map(String.init).joined(separator: ",")); date overrides \(dayPlan.keys.sorted().joined(separator: ","))"
    }

    static func plannedSlotCount(in interval: DateInterval, dayPlan overrides: [String: String]? = nil) -> Int {
        let ids = overrides ?? dayPlan
        var date = calendar.startOfDay(for: interval.start)
        var count = 0
        while date < interval.end {
            if effectiveRoutineID(for: date, dayPlan: ids) != nil { count += 1 }
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return count
    }

    private static var foundationWeek: [Int: String] {
        weekSchedule.reduce(into: [Int: String]()) { result, pair in
            // App: Monday=0...Sunday=6. Foundation: Sunday=1...Saturday=7.
            result[pair.key == 6 ? 1 : pair.key + 2] = pair.value.uuidString
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.string(forKey: key)?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value), let string = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(string, forKey: key)
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
