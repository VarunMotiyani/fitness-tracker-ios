import Foundation
import FitnessDomain
import ExerciseCatalog
import RuleEngine
import Metrics

/// The app-wide source of truth for recurring workout slots and date overrides.
///
/// `PlanView` stores weekdays as Monday-first indices (0...6), while the Core
/// scheduling engine uses Foundation weekday values (Sunday=1...Saturday=7).
/// Keeping that translation here prevents each screen and AI consumer from
/// silently inventing a different schedule.
/// Three date-keyed layers compose the effective workout for a calendar date:
///
///  1. `gym_day_plan_json` (`userDayPlan`)   — the athlete picks a different
///     recurring routine for that date, or marks it "rest".
///  2. `gym_day_plan_auto_json` (`autoDayPlan`) — the missed-session catch-up
///     scheduler's projection, recomputed from scratch on every `refresh`.
///  3. `gym_day_workout_overrides_json` (`dayWorkoutOverrides`) — the exercise
///     list *inside* that date's session is edited (add/replace/remove), stored
///     as a full snapshot.
///
/// Layers 1+2 decide *which* session is scheduled (`plannedSession`); layer 3
/// swaps its items (`effectiveSession`). Every date-specific read goes through
/// `effectiveSession(for:in:)`; only `plan.sessions` reads that intentionally
/// describe the recurring routine stay direct.
enum WorkoutScheduleStore {
    static let scheduleKey = "gym_week_schedule_json"
    /// The athlete's own date overrides (from the day sheet). Never written by
    /// the auto-reschedule.
    static let dayPlanKey = "gym_day_plan_json"
    /// The auto-reschedule's output, recomputed from scratch on every `refresh`.
    /// Kept separate so a session completed on its original day doesn't leave a
    /// stale catch-up baked into the user's plan (which double-counted the week).
    static let autoPlanKey = "gym_day_plan_auto_json"
    /// Date-scoped exercise-list edits (layer 3 above).
    static let dayWorkoutOverrideKey = "gym_day_workout_overrides_json"
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

    // MARK: - Date-scoped exercise-list overrides (layer 3)

    /// A full snapshot of the exercise list in effect for one calendar date.
    /// `baseSessionID` ties it to the session that was scheduled when it was
    /// written; if the schedule later resolves a different session for that
    /// date, the override is ignored (but still removable).
    struct DayWorkoutOverride: Codable, Equatable {
        enum Origin: String, Codable { case manual, ai }
        let dateKey: String
        let baseSessionID: UUID
        let focusMuscles: [MuscleGroup]
        let items: [PlannedItem]
        let origin: Origin
        let updatedAt: Date
    }

    static var dayWorkoutOverrides: [String: DayWorkoutOverride] {
        decode([String: DayWorkoutOverride].self, key: dayWorkoutOverrideKey) ?? [:]
    }

    /// Replaces the entry for `override.dateKey`, always re-stamping `updatedAt`.
    static func saveDayWorkoutOverride(_ override: DayWorkoutOverride) {
        var all = dayWorkoutOverrides
        all[override.dateKey] = DayWorkoutOverride(
            dateKey: override.dateKey, baseSessionID: override.baseSessionID,
            focusMuscles: override.focusMuscles, items: override.items,
            origin: override.origin, updatedAt: .now)
        encode(all, key: dayWorkoutOverrideKey)
    }

    static func removeDayWorkoutOverride(for date: Date) {
        var all = dayWorkoutOverrides
        all.removeValue(forKey: Scheduling.isoDateKey(date, calendar: calendar))
        encode(all, key: dayWorkoutOverrideKey)
    }

    /// The override that actually applies to `date` (matching base session,
    /// non-empty), or nil.
    static func dayWorkoutOverride(for date: Date, in plan: WeeklyPlan) -> DayWorkoutOverride? {
        guard let base = plannedSession(for: date, in: plan),
              let override = dayWorkoutOverrides[Scheduling.isoDateKey(date, calendar: calendar)],
              override.baseSessionID == base.id,
              !override.items.isEmpty
        else { return nil }
        return override
    }

    /// The exercise list actually in effect for `date`: the scheduled session
    /// with a valid same-date `DayWorkoutOverride` applied. Nil when nothing is
    /// scheduled that day. This is the single read path for a scheduled date.
    static func effectiveSession(for date: Date, in plan: WeeklyPlan) -> PlannedSession? {
        guard let base = plannedSession(for: date, in: plan) else { return nil }
        guard let override = dayWorkoutOverride(for: date, in: plan) else { return base }
        return PlannedSession(id: base.id, order: base.order,
                              focusMuscles: base.focusMuscles, items: override.items)
    }

    /// `true` when `exercise` is compatible with the session's shared taxonomy. A custom
    /// focus falls back to its explicit muscle set; named focuses also enforce movement family.
    private static func isCompatible(_ exercise: Exercise, with session: PlannedSession) -> Bool {
        let muscles = Set(session.focusMuscles)
        guard !muscles.isEmpty else { return false }
        let focus = WorkoutFocus.classify(muscles: muscles)
        let definition = focus == .custom
            ? SessionDefinition(focus: .custom, muscles: muscles)
            : WorkoutFocus.definition(for: focus)
        return ExerciseTaxonomy.compatibilityScore(exercise, session: definition) >= 0.35
    }

    private static func persistWorkoutOverride(_ items: [PlannedItem], base: PlannedSession,
                                               on date: Date, origin: DayWorkoutOverride.Origin) {
        saveDayWorkoutOverride(DayWorkoutOverride(
            dateKey: Scheduling.isoDateKey(date, calendar: calendar),
            baseSessionID: base.id, focusMuscles: base.focusMuscles,
            items: items, origin: origin, updatedAt: .now))
    }

    /// Swaps one exercise for `replacement`, keeping the original prescription.
    /// Rejects an off-focus or duplicate replacement, or an unknown existing id.
    @discardableResult
    static func replaceExercise(_ existingID: String, with replacement: Exercise, on date: Date,
                                in plan: WeeklyPlan, catalog: CatalogStore,
                                origin: DayWorkoutOverride.Origin) -> Bool {
        guard let base = plannedSession(for: date, in: plan),
              catalog.exercise(id: replacement.id) != nil,
              isCompatible(replacement, with: base)
        else { return false }
        var items = effectiveSession(for: date, in: plan)?.items ?? base.items
        guard let idx = items.firstIndex(where: { $0.exerciseID == existingID }),
              !items.contains(where: { $0.exerciseID == replacement.id })
        else { return false }
        let old = items[idx]
        items[idx] = PlannedItem(exerciseID: replacement.id, targetSets: old.targetSets,
                                 targetReps: old.targetReps, targetLoadKg: old.targetLoadKg,
                                 restSeconds: old.restSeconds, coachNote: old.coachNote)
        persistWorkoutOverride(items, base: base, on: date, origin: origin)
        return true
    }

    /// Appends `exercise` at 3×8–12, no load, 90s rest. Rejects an off-focus or
    /// duplicate exercise.
    @discardableResult
    static func addExercise(_ exercise: Exercise, on date: Date, in plan: WeeklyPlan,
                            catalog: CatalogStore, origin: DayWorkoutOverride.Origin) -> Bool {
        guard let base = plannedSession(for: date, in: plan),
              catalog.exercise(id: exercise.id) != nil,
              isCompatible(exercise, with: base)
        else { return false }
        var items = effectiveSession(for: date, in: plan)?.items ?? base.items
        guard !items.contains(where: { $0.exerciseID == exercise.id }) else { return false }
        items.append(PlannedItem(exerciseID: exercise.id, targetSets: 3,
                                 targetReps: RepRange(min: 8, max: 12), targetLoadKg: nil,
                                 restSeconds: 90, coachNote: ""))
        persistWorkoutOverride(items, base: base, on: date, origin: origin)
        return true
    }

    /// Drops one exercise. Refuses to leave the session empty or to remove an
    /// exercise that isn't in it.
    @discardableResult
    static func removeExercise(_ exerciseID: String, on date: Date, in plan: WeeklyPlan) -> Bool {
        guard let base = plannedSession(for: date, in: plan) else { return false }
        var items = effectiveSession(for: date, in: plan)?.items ?? base.items
        guard items.contains(where: { $0.exerciseID == exerciseID }), items.count > 1 else { return false }
        items.removeAll { $0.exerciseID == exerciseID }
        let key = Scheduling.isoDateKey(date, calendar: calendar)
        persistWorkoutOverride(items, base: base, on: date,
                               origin: dayWorkoutOverrides[key]?.origin ?? .manual)
        return true
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

    /// Decoded-value cache keyed by the raw stored string. Every screen reads
    /// these properties dozens of times per frame (the 7-day week strip alone
    /// calls `effectiveRoutineID` seven times, each hitting `dayPlan` twice);
    /// re-running `JSONDecoder` each time was a measurable on-device hitch.
    /// Comparing the raw string means writes from anywhere — `encode` here, a
    /// backup restore, a direct `UserDefaults.set` — invalidate it for free.
    private static var decodeCache: [String: (raw: String?, value: Any?)] = [:]

    private static func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        let raw = UserDefaults.standard.string(forKey: key)
        if let hit = decodeCache[key], hit.raw == raw {
            return hit.value as? T
        }
        let decoded: T? = raw?.data(using: .utf8).flatMap { try? JSONDecoder().decode(type, from: $0) }
        decodeCache[key] = (raw, decoded)
        return decoded
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
