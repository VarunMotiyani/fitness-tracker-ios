import Foundation
import SwiftData
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif
import FitnessDomain
import ExerciseCatalog
import Metrics
import CoachMemory
import LLMKit
import RuleEngine

nonisolated struct ProactiveSettings: Sendable {
    var dailyOn: Bool
    var weeklyOn: Bool
    var inbodyOn: Bool
    var checkinOn: Bool
    var patternOn: Bool
    var reminderHour: Int
    var reminderMinute: Int
}

/// Reads the exact same `UserDefaults` keys/defaults `RootView`'s
/// `@AppStorage` properties do, for the one caller that has no SwiftUI
/// environment to read them from: `ProactiveBackgroundScheduler`'s task
/// handler. `@AppStorage` is itself just a `UserDefaults.standard` wrapper,
/// so this reads the same live values RootView would show, not a stale copy.
nonisolated enum ProactiveSettingsStore {
    static func current() -> ProactiveSettings {
        let d = UserDefaults.standard
        func bool(_ key: String, default def: Bool) -> Bool {
            d.object(forKey: key) == nil ? def : d.bool(forKey: key)
        }
        func int(_ key: String, default def: Int) -> Int {
            d.object(forKey: key) == nil ? def : d.integer(forKey: key)
        }
        return ProactiveSettings(
            dailyOn: bool("proactive.settings.daily", default: true),
            weeklyOn: bool("proactive.settings.weekly", default: true),
            inbodyOn: bool("proactive.settings.inbody", default: true),
            checkinOn: bool("proactive.settings.checkin", default: true),
            patternOn: bool("proactive.settings.pattern", default: true),
            reminderHour: int("gym_reminder_hour", default: 18),
            reminderMinute: int("gym_reminder_minute", default: 0)
        )
    }
}

/// The proactive layer (design spec §3). Run from `RootView` on every
/// app-foreground. Generates LLM text while the app is open and bakes it into
/// scheduled notifications, since iOS can't call an LLM at fire time.
@MainActor
struct ProactiveCoordinator {
    let context: ModelContext
    let catalog: CatalogStore
    let provider: (any LLMProvider)?
    let activeProfile: ProviderProfile?
    let settings: ProactiveSettings

    private let notificationCenter = UNUserNotificationCenter.current()
    private static var isRunning = false
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = .appWeek
        f.timeZone = .autoupdatingCurrent
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    func runDueChecks() async {
        guard !Self.isRunning else { return }
        Self.isRunning = true
        defer { Self.isRunning = false }

        let completed = (try? context.fetch(FetchDescriptor<CompletedSessionModel>())) ?? []
        let reschedule = WorkoutScheduleStore.refresh(completedSessions: completed, plan: mostRecentPlan())
        if settings.weeklyOn { await reactToMissedWeek(reschedule.unplaced) }

        if settings.inbodyOn { await scheduleInBodyReminderIfNeeded() }
        else { notificationCenter.removePendingNotificationRequests(withIdentifiers: ["proactive_inbody"]) }

        // Sweep stale patternNudge keys before the provider guard — orphan
        // cleanup must run even when there's no LLM configured.
        if settings.patternOn { pruneOrphanPatternNudgeKeys() }
        if settings.patternOn { refreshDataInsights() }

        guard provider != nil else {
            if settings.dailyOn, isDailyDue() { generateFallbackDaily() }
            if settings.weeklyOn, isWeeklyDue() { generateFallbackWeekly() }
            return
        }

        if settings.dailyOn, isDailyDue() { await generateDailyNarration() }
        if settings.weeklyOn, isWeeklyDue() { await generateWeeklySummary() }      // Task 4
        if settings.patternOn { await runPatternNudges() }                        // Task 5
    }

    // MARK: - Daily narration (#6)

    private func isDailyDue() -> Bool {
        UserDefaults.standard.string(forKey: "proactive.daily.lastGeneratedDay") != Self.dayFormatter.string(from: .now)
    }

    private func generateDailyNarration() async {
        guard let provider,
              let plan = mostRecentPlan(),
              let session = todaysOrNextSession(in: plan)
        else { return }

        let sessionLabel = session.focusMuscles.map { $0.rawValue.capitalized }.joined(separator: "/") + " Day"
        let exerciseNames = session.items.compactMap { catalog.exercise(id: $0.exerciseID)?.name }
        let recoveryDigest = recoveryDigest()
        let memoryDigest = memoryDigest()

        let system = ProactivePromptBuilder.system()
        let user = ProactivePromptBuilder.userDailyNarration(
            sessionLabel: sessionLabel, exerciseNames: exerciseNames,
            recoveryDigest: recoveryDigest, memoryDigest: memoryDigest)

        do {
            let result: ToolLoopResult<DailyNarrationDTO> = try await ToolLoopRunner().run(
                system: system, initialUser: user,
                finalSchema: ProactivePromptBuilder.dailyNarrationSchema,
                tools: ToolRegistry(tools: []), provider: provider)
            recordCalls(result.calls, callType: "dailyNarration")
            let text = result.value.narration
            let scheduleContext = WorkoutScheduleStore.isRescheduled(for: .now) ? " It was moved here automatically to recover a missed weekday." : ""
            let reason = "Based on today’s \(sessionLabel) session, its planned exercises, and the latest recovery check-in available to the coach.\(scheduleContext)"
            upsertCurrentCoachNote(kindRaw: "daily", text: text, reason: reason, period: .day)
            _ = PersistenceReporter.attemptSave(context, operation: "persist context")
            scheduleDaily(body: text)
            UserDefaults.standard.set(Self.dayFormatter.string(from: .now), forKey: "proactive.daily.lastGeneratedDay")
        } catch ToolLoopError.exceededMaxIterations(let calls) {
            recordCalls(calls, callType: "dailyNarration")
            generateFallbackDaily()
        } catch ToolLoopError.providerFailed(let calls), ToolLoopError.providerFailedWithMessage(let calls, _) {
            recordCalls(calls, callType: "dailyNarration")
            generateFallbackDaily()
        } catch { generateFallbackDaily() }
    }

    private func scheduleDaily(body: String) {
        let content = UNMutableNotificationContent()
        content.title = "From your coach"
        content.body = body
        content.sound = .default
        content.userInfo = ["proactive": "daily"]
        var dc = DateComponents(); dc.hour = settings.reminderHour; dc.minute = settings.reminderMinute
        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ["proactive_daily"])

        // If today's reminder time has already passed, a non-repeating calendar
        // trigger would fire tomorrow — skip it. The Home CoachNoteModel already
        // covers the user for today. `reminderHour/Minute` are local wall-clock
        // values and the trigger resolves in the local calendar, so compare in
        // `Calendar.current` — NOT the UTC calendar used for day/week bucketing.
        let cal = Calendar.current
        let now = Date()
        if let fireToday = cal.date(bySettingHour: settings.reminderHour, minute: settings.reminderMinute,
                                    second: 0, of: now),
           fireToday <= now {
            return
        }
        notificationCenter.add(UNNotificationRequest(identifier: "proactive_daily", content: content, trigger: trigger))
    }

    // MARK: - InBody reminder (#8) — no LLM

    /// (Re)build the InBody request unconditionally — removes any stale copy
    /// first, then adds a fresh 5-week repeating trigger. Callers decide
    /// whether a rebuild is wanted; this does not itself check for a pending
    /// request.
    private func installInBodyReminder() {
        let content = UNMutableNotificationContent()
        content.title = "InBody scan due"
        content.body = "It's been about 5 weeks — take a scan and tell your coach the numbers in chat."
        content.sound = .default
        let fiveWeeks: TimeInterval = 5 * 7 * 24 * 3600
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fiveWeeks, repeats: true)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ["proactive_inbody"])
        notificationCenter.add(
            UNNotificationRequest(identifier: "proactive_inbody", content: content, trigger: trigger))
    }

    /// The `runDueChecks` path: only (re)install when nothing is pending, so a
    /// normal foreground launch doesn't reset the 5-week clock every time.
    private func scheduleInBodyReminderIfNeeded() async {
        let pending = await notificationCenter.pendingNotificationRequests()
        guard !pending.contains(where: { $0.identifier == "proactive_inbody" }) else { return }
        installInBodyReminder()
    }

    /// Call when a body-composition observation is confirmed so the 5-week
    /// clock restarts. A reset *must* replace the request, so install
    /// directly and unconditionally — no pending-check.
    func resetInBodyReminder() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ["proactive_inbody"])
        if settings.inbodyOn { installInBodyReminder() }
    }

    // MARK: - Weekly (#7) — Task 4 fills this

    /// The Monday-anchored week the weekly recap should currently cover, and its
    /// full Mon–Sun interval. On Sunday it's the week ending today; on Mon–Sat
    /// it's the week that just finished — so a recap the athlete skipped on
    /// Sunday is still delivered the next day, until the following Sunday
    /// supersedes it. Uses the device's own calendar/time zone.
    private func recapWeek() -> (start: Date, interval: DateInterval)? {
        let cal = Calendar.appWeek
        let today = cal.startOfDay(for: .now)
        let daysFromMonday = (cal.component(.weekday, from: today) + 5) % 7 // Mon=0 … Sun=6
        guard let thisMonday = cal.date(byAdding: .day, value: -daysFromMonday, to: today) else { return nil }
        let start = daysFromMonday == 6
            ? thisMonday
            : (cal.date(byAdding: .day, value: -7, to: thisMonday) ?? thisMonday)
        guard let end = cal.date(byAdding: .day, value: 7, to: start) else { return nil }
        return (start, DateInterval(start: start, end: end))
    }

    private func recapWeekKey(_ start: Date) -> String { ISO8601DateFormatter().string(from: start) }

    /// The dedup key the weekly recap currently targets — exposed for tests.
    func currentRecapWeekKey() -> String? { recapWeek().map { recapWeekKey($0.start) } }

    func isWeeklyDue() -> Bool {
        guard let week = recapWeek() else { return false }
        return UserDefaults.standard.string(forKey: "proactive.weekly.lastWeekStart") != recapWeekKey(week.start)
    }

    private func generateWeeklySummary() async {
        guard let provider, let week = recapWeek() else { return }
        let interval = week.interval

        let allSessions = (try? context.fetch(FetchDescriptor<CompletedSessionModel>())) ?? []
        let weekSessions = allSessions.filter { $0.finishedAt.map(interval.contains) ?? false }
        let snapshots = allSessions.filter { $0.finishedAt != nil }.map { $0.toSnapshot() }
        let plannedPerWeek = effectivePlannedPerWeek(in: interval, fallback: (try? context.fetch(FetchDescriptor<UserProfile>()))?.first?.sessionsPerWeek ?? 3)
        let streak = StreakCalculator.computeSummary(from: snapshots, plannedPerWeek: plannedPerWeek).currentStreakWeeks
        let prCount = ((try? context.fetch(FetchDescriptor<PersonalRecordModel>())) ?? [])
            .filter { interval.contains($0.date) }.count

        // Muscle coverage over the prior week — mirror the EffectiveSetItem loop
        // the other coordinators build.
        var items: [MuscleBalanceModel.EffectiveSetItem] = []
        for s in weekSessions {
            for e in s.entries where !e.skipped {
                guard let ex = catalog.exercise(id: e.exerciseID) else { continue }
                let doneSets = e.sets.filter { !$0.isWarmup }.count
                if doneSets > 0 { items.append(.init(exercise: ex, sets: doneSets)) }
            }
        }
        let (_, missed) = MuscleBalanceModel.rankOf(load: MuscleBalanceModel.loadOf(items: items))
        let coverageDigest = missed.isEmpty
            ? "all major muscles trained"
            : "undertrained: \(missed.map { MuscleBalanceModel.displayName(for: $0) }.joined(separator: ", "))"

        let system = ProactivePromptBuilder.system()
        let user = ProactivePromptBuilder.userWeeklySummary(
            sessionsCompleted: weekSessions.count, plannedPerWeek: plannedPerWeek, streakWeeks: streak,
            muscleCoverageDigest: coverageDigest, prCount: prCount, memoryDigest: memoryDigest())

        do {
            let result: ToolLoopResult<WeeklySummaryDTO> = try await ToolLoopRunner().run(
                system: system, initialUser: user,
                finalSchema: ProactivePromptBuilder.weeklySummarySchema,
                tools: ToolRegistry(tools: []), provider: provider)
            recordCalls(result.calls, callType: "weeklySummary")
            let dto = result.value

            // One WeeklySummaryModel row per recap week, stamped and deduped on
            // that week's Monday.
            let existing = ((try? context.fetch(FetchDescriptor<WeeklySummaryModel>())) ?? [])
                .first { Calendar.appWeek.isDate($0.weekStartDate, inSameDayAs: week.start) }
            if let existing {
                existing.headline = dto.headline
                existing.summaryBody = dto.body
                existing.nextWeekFocus = dto.nextWeekFocus
                existing.generatedAt = .now
            } else {
                context.insert(WeeklySummaryModel(weekStartDate: week.start, headline: dto.headline,
                    summaryBody: dto.body, nextWeekFocus: dto.nextWeekFocus))
            }
            // The Home `thisWeekCard` already surfaces `headline` persistently;
            // the CoachNote carries the complementary next-week focus instead.
            let reason = "Based on \(weekSessions.count) completed sessions, a \(streak)-week streak, \(prCount) PRs, and the week’s muscle coverage (\(coverageDigest))."
            upsertCurrentCoachNote(kindRaw: "weekly", text: "Next week: \(dto.nextWeekFocus)", reason: reason, period: .weekOfYear)
            _ = PersistenceReporter.attemptSave(context, operation: "persist context")
            scheduleWeekly(body: dto.headline)
            UserDefaults.standard.set(recapWeekKey(week.start), forKey: "proactive.weekly.lastWeekStart")
        } catch ToolLoopError.exceededMaxIterations(let calls) {
            recordCalls(calls, callType: "weeklySummary")
            generateFallbackWeekly()
        } catch ToolLoopError.providerFailed(let calls), ToolLoopError.providerFailedWithMessage(let calls, _) {
            recordCalls(calls, callType: "weeklySummary")
            generateFallbackWeekly()
        } catch { generateFallbackWeekly() }
    }

    /// Keeps the current daily card useful when no provider is configured or
    /// an AI request fails. A later successful AI run upserts this same row.
    private func generateFallbackDaily() {
        guard let plan = mostRecentPlan(), let session = todaysOrNextSession(in: plan) else { return }
        let label = session.focusMuscles.map { $0.rawValue.capitalized }.joined(separator: "/") + " Day"
        let names = session.items.compactMap { catalog.exercise(id: $0.exerciseID)?.name }
        let exerciseSummary = names.prefix(3).joined(separator: ", ")
        let suffix = names.count > 3 ? " and " + String(names.count - 3) + " more" : ""
        let text: String
        if exerciseSummary.isEmpty {
            text = label + " today. Keep the session controlled and leave a little in reserve on your working sets."
        } else {
            text = label + " today: " + exerciseSummary + suffix + ". Keep the reps controlled and leave 1–3 reps in reserve on your working sets."
        }
        let reason = "Offline summary from today’s planned session and its " + String(names.count) + " scheduled exercises."
        upsertCurrentCoachNote(kindRaw: "daily", text: text, reason: reason, period: .day)
        _ = PersistenceReporter.attemptSave(context, operation: "persist context")
        UserDefaults.standard.set(Self.dayFormatter.string(from: .now), forKey: "proactive.daily.lastGeneratedDay")
    }

    /// Provides a transparent, data-backed weekly card while an AI provider is
    /// unavailable. It is replaced by the richer generated recap when possible.
    private func generateFallbackWeekly() {
        guard let week = recapWeek() else { return }
        let interval = week.interval
        let sessions = ((try? context.fetch(FetchDescriptor<CompletedSessionModel>())) ?? [])
            .filter { $0.finishedAt.map(interval.contains) ?? false }
        let prs = ((try? context.fetch(FetchDescriptor<PersonalRecordModel>())) ?? [])
            .filter { interval.contains($0.date) }.count
        let planned = effectivePlannedPerWeek(in: interval, fallback: (try? context.fetch(FetchDescriptor<UserProfile>()))?.first?.sessionsPerWeek ?? 3)
        let focus = sessions.isEmpty ? "getting your next session on the calendar" : "keeping your working sets consistent"
        let text = "Last week: " + String(sessions.count) + " sessions and " + String(prs) + " new PRs. Next week, focus on " + focus + "."
        let reason = "Offline recap from " + String(sessions.count) + " completed sessions, " + String(prs) + " PRs, and a plan target of " + String(planned) + " sessions per week."
        upsertCurrentCoachNote(kindRaw: "weekly", text: text, reason: reason, period: .weekOfYear)
        _ = PersistenceReporter.attemptSave(context, operation: "persist context")
        UserDefaults.standard.set(recapWeekKey(week.start), forKey: "proactive.weekly.lastWeekStart")
    }

    // MARK: - Missed-week scold (#10)

    /// The catch-up scheduler moves every missed session to a free day, but when
    /// the week runs out of room some can't be placed — `unplaced`. Those don't
    /// vanish quietly: the coach calls it out (a taunt + what got skipped), once
    /// per week. Runs with or without a provider — a canned taunt when offline.
    func reactToMissedWeek(_ unplaced: [Scheduling.MissedSessionReschedule.Unplaced]) async {
        guard !unplaced.isEmpty,
              let week = Calendar.appWeek.dateInterval(of: .weekOfYear, for: .now) else { return }

        let weekKey = ISO8601DateFormatter().string(from: week.start)
        guard UserDefaults.standard.string(forKey: "proactive.missedWeek.lastWeekStart") != weekKey else { return }

        let weekSessions = ((try? context.fetch(FetchDescriptor<CompletedSessionModel>())) ?? [])
            .filter { $0.finishedAt.map(week.contains) ?? false }
        let planned = effectivePlannedPerWeek(
            in: week, fallback: (try? context.fetch(FetchDescriptor<UserProfile>()))?.first?.sessionsPerWeek ?? 3)

        var items: [MuscleBalanceModel.EffectiveSetItem] = []
        for s in weekSessions {
            for e in s.entries where !e.skipped {
                guard let ex = catalog.exercise(id: e.exerciseID) else { continue }
                let doneSets = e.sets.filter { !$0.isWarmup }.count
                if doneSets > 0 { items.append(.init(exercise: ex, sets: doneSets)) }
            }
        }
        let (_, missedMuscles) = MuscleBalanceModel.rankOf(load: MuscleBalanceModel.loadOf(items: items))
        let skippedDigest = missedMuscles.map { MuscleBalanceModel.displayName(for: $0) }.joined(separator: ", ")

        let count = unplaced.count
        let reason = "\(count) planned session\(count == 1 ? "" : "s") had no day left to reschedule into this week (\(weekSessions.count) of \(planned) completed)."

        if let provider {
            let user = ProactivePromptBuilder.userMissedWeekTaunt(
                missedCount: count, completedThisWeek: weekSessions.count, plannedPerWeek: planned,
                skippedMusclesDigest: skippedDigest, memoryDigest: memoryDigest())
            do {
                let result: ToolLoopResult<MissedWeekTauntDTO> = try await ToolLoopRunner().run(
                    system: ProactivePromptBuilder.system(), initialUser: user,
                    finalSchema: ProactivePromptBuilder.missedWeekTauntSchema,
                    tools: ToolRegistry(tools: []), provider: provider)
                recordCalls(result.calls, callType: "missedWeek")
                upsertCurrentCoachNote(kindRaw: "missedWeek", text: result.value.taunt, reason: reason, period: .weekOfYear)
                _ = PersistenceReporter.attemptSave(context, operation: "persist context")
                UserDefaults.standard.set(weekKey, forKey: "proactive.missedWeek.lastWeekStart")
                return
            } catch ToolLoopError.exceededMaxIterations(let calls) {
                recordCalls(calls, callType: "missedWeek")
            } catch ToolLoopError.providerFailed(let calls), ToolLoopError.providerFailedWithMessage(let calls, _) {
                recordCalls(calls, callType: "missedWeek")
            } catch {}
        }

        let musclesLine = skippedDigest.isEmpty ? "" : " You left \(skippedDigest) untouched."
        let text = "\(count) session\(count == 1 ? "" : "s") got away from you and there's no day left this week to make \(count == 1 ? "it" : "them") up — \(weekSessions.count) of \(planned) done.\(musclesLine) Next week starts Monday. Show up."
        upsertCurrentCoachNote(kindRaw: "missedWeek", text: text, reason: reason, period: .weekOfYear)
        _ = PersistenceReporter.attemptSave(context, operation: "persist context")
        UserDefaults.standard.set(weekKey, forKey: "proactive.missedWeek.lastWeekStart")
    }

    private func scheduleWeekly(body: String) {
        let content = UNMutableNotificationContent()
        content.title = "Your week in review"
        content.body = body
        content.sound = .default
        content.userInfo = ["proactive": "weekly"]
        // ~1 minute out — the summary is already generated and persisted; the
        // notification is just the ping to go read it.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ["proactive_weekly"])
        notificationCenter.add(UNNotificationRequest(identifier: "proactive_weekly", content: content, trigger: trigger))
    }

    // MARK: - Pattern nudge (#10) — Task 5 fills this

    /// Produce a small set of explainable, offline insights from the athlete's
    /// own history. These are intentionally deterministic and cheap: no extra
    /// provider call is needed, and each topic is upserted once per day.
    private func refreshDataInsights() {
        let sessions = ((try? context.fetch(FetchDescriptor<CompletedSessionModel>())) ?? [])
            .filter { $0.finishedAt != nil }
        guard !sessions.isEmpty else { return }

        let now = Date.now
        let calendar = Calendar.current
        guard let recentStart = calendar.date(byAdding: .day, value: -28, to: now),
              let previousStart = calendar.date(byAdding: .day, value: -56, to: now) else { return }
        let recent = sessions.filter { ($0.finishedAt ?? $0.startedAt) >= recentStart }
        let previous = sessions.filter {
            let date = $0.finishedAt ?? $0.startedAt
            return date >= previousStart && date < recentStart
        }
        var candidates: [(topic: String, text: String, reason: String)] = []

        let targetPerFourWeeks = ((try? context.fetch(FetchDescriptor<UserProfile>()))?.first?.sessionsPerWeek ?? 3) * 4
        candidates.append((
            "consistency",
            "You completed \(recent.count) sessions in the last 4 weeks.",
            "Compared with your profile target of \(targetPerFourWeeks) sessions over the same four-week window."
        ))

        let recentSets = workingSetCount(in: recent)
        let previousSets = workingSetCount(in: previous)
        if previousSets > 0 {
            let change = Int((Double(recentSets - previousSets) / Double(previousSets) * 100).rounded())
            let direction = change >= 0 ? "up" : "down"
            candidates.append((
                "volume",
                "Working-set volume is \(abs(change))% \(direction) versus the previous 4 weeks.",
                "Compared \(recentSets) working sets in the last 28 days with \(previousSets) in the 28 days before that; warm-ups and skipped entries are excluded."
            ))
        } else if recentSets > 0 {
            candidates.append((
                "volume",
                "You logged \(recentSets) working sets in the last 4 weeks.",
                "Counted completed, non-warm-up sets across your finished sessions."
            ))
        }

        if let progression = strongestProgression(in: sessions) {
            candidates.append(progression)
        }

        let rirValues = workingSets(in: recent).compactMap(\.rir)
        if !rirValues.isEmpty {
            let average = rirValues.reduce(0, +) / Double(rirValues.count)
            let hardShare = Int((Double(rirValues.filter { $0 <= 2 }.count) / Double(rirValues.count) * 100).rounded())
            candidates.append((
                "effort",
                "Your recent sets average \(average.formatted(.number.precision(.fractionLength(1)))) RIR.",
                "Based on \(rirValues.count) rated working sets; \(hardShare)% were at 2 RIR or harder."
            ))
        }

        for candidate in candidates.prefix(4) {
            upsertCurrentCoachNote(kindRaw: "analysis", text: candidate.text, reason: candidate.reason,
                                   period: .day, topicRaw: candidate.topic)
        }
    }

    private func workingSets(in sessions: [CompletedSessionModel]) -> [LoggedSetModel] {
        sessions.flatMap { session in
            session.entries.filter { !$0.skipped }.flatMap { entry in
                entry.sets.filter { !$0.isWarmup }
            }
        }
    }

    private func workingSetCount(in sessions: [CompletedSessionModel]) -> Int {
        workingSets(in: sessions).count
    }

    private func strongestProgression(in sessions: [CompletedSessionModel]) -> (topic: String, text: String, reason: String)? {
        var loadsByExercise: [String: [(date: Date, load: Double)]] = [:]
        for session in sessions {
            let date = session.finishedAt ?? session.startedAt
            for entry in session.entries where !entry.skipped {
                let loads = entry.sets.filter { !$0.isWarmup && $0.actualLoadKg > 0 }.map { $0.actualLoadKg }
                guard let maxLoad = loads.max() else { continue }
                loadsByExercise[entry.exerciseID, default: []].append((date, maxLoad))
            }
        }

        let best = loadsByExercise.compactMap { exerciseID, values -> (String, Double, Double)? in
            let sorted = values.sorted { $0.date < $1.date }
            guard sorted.count >= 2, let latest = sorted.last?.load,
                  let previous = sorted.dropLast().last?.load, latest > previous else { return nil }
            return (exerciseID, latest, previous)
        }.max { ($0.1 - $0.2) < ($1.1 - $1.2) }
        guard let best, let exercise = catalog.exercise(id: best.0) else { return nil }
        let delta = best.1 - best.2
        return (
            "progression",
            "\(exercise.name) is moving up by \(delta.formatted(.number.precision(.fractionLength(1)))) kg.",
            "Your latest recorded top load was \(best.1.formatted(.number.precision(.fractionLength(1)))) kg versus \(best.2.formatted(.number.precision(.fractionLength(1)))) kg previously."
        )
    }

    /// Drop `proactive.patternNudge.<uuid>` UserDefaults keys whose memory no
    /// longer exists. Keys for still-live `responsePattern` memories stay, even
    /// if their confidence has since dropped below the 0.6 nudge threshold.
    private func pruneOrphanPatternNudgeKeys() {
        let liveIDs = Set(((try? context.fetch(FetchDescriptor<CoachMemoryModel>())) ?? [])
            .filter { $0.kindRaw == "responsePattern" }
            .map { $0.id.uuidString })
        let prefix = "proactive.patternNudge."
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            if !liveIDs.contains(String(key.dropFirst(prefix.count))) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    /// Not `private` — also called immediately after a memory write from
    /// `AskCoachCoordinator`/`MemoryKeeperCoordinator`, instead of only on
    /// `runDueChecks`'s own app-open/background schedule.
    func runPatternNudges() async {
        guard let provider else { return }
        let candidates = ((try? context.fetch(FetchDescriptor<CoachMemoryModel>())) ?? [])
            .filter { $0.kindRaw == "responsePattern" && $0.confidence >= 0.6 && $0.supersededBy == nil && !$0.retiredByCap }
            .filter { mem in
                let key = "proactive.patternNudge.\(mem.id.uuidString)"
                guard let s = UserDefaults.standard.string(forKey: key),
                      let last = ISO8601DateFormatter().date(from: s) else { return true }
                return Date().timeIntervalSince(last) > 14 * 24 * 3600
            }
            .sorted { $0.confidence > $1.confidence }

        guard let target = candidates.first else { return }

        let recentDigest = recentSessionsDigest(limit: 5)
        let system = ProactivePromptBuilder.system()
        let user = ProactivePromptBuilder.userPatternNudge(
            patternStatement: target.statement, recentSessionsDigest: recentDigest, memoryDigest: memoryDigest())

        do {
            let result: ToolLoopResult<PatternNudgeDTO> = try await ToolLoopRunner().run(
                system: system, initialUser: user, finalSchema: ProactivePromptBuilder.patternNudgeSchema,
                tools: ToolRegistry(tools: []), provider: provider)
            recordCalls(result.calls, callType: "patternNudge")
            context.insert(CoachNoteModel(kindRaw: "pattern", text: result.value.nudge,
                                          reason: "This was generated from the recurring pattern: \(target.statement)",
                                          topicRaw: target.id.uuidString))
            _ = PersistenceReporter.attemptSave(context, operation: "persist context")
            UserDefaults.standard.set(ISO8601DateFormatter().string(from: .now),
                                      forKey: "proactive.patternNudge.\(target.id.uuidString)")
        } catch ToolLoopError.exceededMaxIterations(let calls) {
            recordCalls(calls, callType: "patternNudge")
        } catch ToolLoopError.providerFailed(let calls), ToolLoopError.providerFailedWithMessage(let calls, _) {
            recordCalls(calls, callType: "patternNudge")
        } catch { return }
    }

    private func recentSessionsDigest(limit: Int) -> String {
        ((try? context.fetch(FetchDescriptor<CompletedSessionModel>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))) ?? [])
            .prefix(limit)
            .map { s in
                let day = Self.dayFormatter.string(from: s.startedAt)
                let names = s.entries.sorted { $0.performedOrder < $1.performedOrder }
                    .compactMap { catalog.exercise(id: $0.exerciseID)?.name }.prefix(3)
                return "\(day): \(names.joined(separator: ", "))"
            }
            .joined(separator: "\n")
    }

    // MARK: - Check-in reaction (#9) — Task 6 fills this

    func reactToCheckin(_ checkin: DailyCheckinModel) async {
        guard settings.checkinOn, let provider else { return }
        let sorenessHigh = (checkin.soreness ?? 0) >= 7
        let sleepLow = checkin.sleepQuality.map { $0 <= 3 } ?? false
        guard sorenessHigh || sleepLow else { return }

        // Per-day dedup — `CheckinEntryView.save()` re-upserts today's row on
        // every Save and calls this unconditionally; without this each re-save
        // burns an LLM call.
        let todayKey = Self.dayFormatter.string(from: .now)
        let lastReacted = UserDefaults.standard.string(forKey: "proactive.checkin.lastReactedDay")
        guard lastReacted != todayKey else { return }

        let system = ProactivePromptBuilder.system()
        let user = ProactivePromptBuilder.userCheckinReaction(
            soreness: checkin.soreness, sleepQuality: checkin.sleepQuality, note: checkin.note,
            recentSessionsDigest: recentSessionsDigest(limit: 3), memoryDigest: memoryDigest())

        do {
            let result: ToolLoopResult<CheckinReactionDTO> = try await ToolLoopRunner().run(
                system: system, initialUser: user, finalSchema: ProactivePromptBuilder.checkinReactionSchema,
                tools: ToolRegistry(tools: []), provider: provider)
            recordCalls(result.calls, callType: "checkinReaction")
            let text = result.value.message
            context.insert(CoachNoteModel(kindRaw: "checkin", text: text,
                                          reason: "Based on today’s check-in: soreness \(checkin.soreness.map(String.init) ?? "not rated")/10 and sleep \(checkin.sleepQuality.map(String.init) ?? "not rated")/10.",
                                          topicRaw: todayKey))
            _ = PersistenceReporter.attemptSave(context, operation: "persist context")
            UserDefaults.standard.set(todayKey, forKey: "proactive.checkin.lastReactedDay")

            // Ping only if the app isn't foreground when the reaction lands.
            var appIsActive = false
            #if canImport(UIKit)
            appIsActive = UIApplication.shared.applicationState == .active
            #endif
            if !appIsActive {
                let content = UNMutableNotificationContent()
                content.title = "From your coach"
                content.body = text
                content.sound = .default
                content.userInfo = ["proactive": "checkin"]
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2 * 3600, repeats: false)
                notificationCenter.removePendingNotificationRequests(withIdentifiers: ["proactive_checkin"])
                notificationCenter.add(UNNotificationRequest(identifier: "proactive_checkin", content: content, trigger: trigger),
                                       withCompletionHandler: nil)
            }
        } catch ToolLoopError.exceededMaxIterations(let calls) {
            recordCalls(calls, callType: "checkinReaction")
        } catch ToolLoopError.providerFailed(let calls), ToolLoopError.providerFailedWithMessage(let calls, _) {
            recordCalls(calls, callType: "checkinReaction")
        } catch { return }
    }

    // MARK: - Shared helpers

    /// Daily and weekly guidance represent the current period, not an inbox
    /// history. Replace the current-period row so repeated foreground checks
    /// cannot create duplicate cards.
    private func upsertCurrentCoachNote(kindRaw: String, text: String, reason: String,
                                        period: Calendar.Component, topicRaw: String? = nil) {
        let calendar = Calendar.current
        let existing = ((try? context.fetch(FetchDescriptor<CoachNoteModel>())) ?? [])
            .filter { $0.kindRaw == kindRaw }
            .filter {
                switch period {
                case .day: return calendar.isDateInToday($0.createdAt)
                case .weekOfYear:
                    return calendar.isDate($0.createdAt, equalTo: Date.now, toGranularity: .weekOfYear)
                default: return false
                }
            }
            .max { $0.createdAt < $1.createdAt }

        if let existing {
            let changed = existing.text != text || existing.reason != reason
            existing.text = text
            existing.reason = reason
            existing.topicRaw = topicRaw ?? existing.topicRaw
            existing.createdAt = Date.now
            if changed { existing.readAt = nil }
        } else {
            context.insert(CoachNoteModel(kindRaw: kindRaw, text: text, reason: reason, topicRaw: topicRaw))
        }
    }

    private func mostRecentPlan() -> WeeklyPlan? {
        (try? context.fetch(FetchDescriptor<StoredPlan>(sortBy: [SortDescriptor(\.generatedAt, order: .reverse)])))?
            .first.flatMap { try? $0.decodedPlan() }
    }

    /// Today's planned session if it hasn't been completed yet, else the next
    /// not-yet-completed one in `order`.
    private func todaysOrNextSession(in plan: WeeklyPlan) -> PlannedSession? {
        let ordered = plan.sessions.sorted { $0.order < $1.order }
        guard let weekStart = Calendar.appWeek.dateInterval(of: .weekOfYear, for: .now)?.start else { return ordered.first }
        let startedThisWeek = Set(((try? context.fetch(FetchDescriptor<CompletedSessionModel>())) ?? [])
            .filter { $0.startedAt >= weekStart }
            .compactMap(\.plannedSessionID))
        for offset in 0..<7 {
            guard let date = Calendar.appWeek.date(byAdding: .day, value: offset, to: Calendar.appWeek.startOfDay(for: .now)),
                  let session = WorkoutScheduleStore.effectiveSession(for: date, in: plan),
                  !startedThisWeek.contains(session.id) else { continue }
            return session
        }
        return ordered.first { !startedThisWeek.contains($0.id) } ?? ordered.first
    }

    private func effectivePlannedPerWeek(in interval: DateInterval, fallback: Int) -> Int {
        let count = WorkoutScheduleStore.plannedSlotCount(in: interval)
        return count > 0 ? count : fallback
    }

    private func recoveryDigest() -> String {
        let snapshots = ((try? context.fetch(FetchDescriptor<CompletedSessionModel>())) ?? []).map { $0.toSnapshot() }
        let statuses = RecoveryModel.computeRecovery(from: snapshots, catalog: catalog, now: .now)
        return statuses
            .sorted { $0.value.fatigueScore < $1.value.fatigueScore }
            .prefix(4)
            .map { "\($0.key.rawValue): \($0.value.state.rawValue)" }
            .joined(separator: ", ")
    }

    private func memoryDigest() -> String {
        let mems = ((try? context.fetch(FetchDescriptor<CoachMemoryModel>())) ?? []).map { $0.toDomain() }
        return MemoryRecall.select(from: mems, context: RecallContext(), now: .now).digest
    }

    func recordCalls(_ calls: [CallOutcome], callType: String) {
        guard !calls.isEmpty else { return }
        for call in calls {
            let cost: Double
            if let p = activeProfile {
                cost = AICallRecord.cost(inputTokens: call.inputTokens, outputTokens: call.outputTokens,
                                         cachedTokens: call.cachedTokens,
                                         pricePerMTokIn: p.pricePerMTokIn, pricePerMTokOut: p.pricePerMTokOut,
                                         pricePerMTokCached: p.pricePerMTokCached)
            } else { cost = 0 }
            context.insert(AICallRecord(callType: callType,
                providerDisplayName: activeProfile?.displayName ?? "—",
                modelID: activeProfile?.modelID ?? "—",
                inputTokens: call.inputTokens, outputTokens: call.outputTokens,
                cachedTokens: call.cachedTokens, costUSD: cost,
                success: call.succeeded, usedFallback: call.usedFallback,
                durationMs: call.durationMs))
        }
        _ = PersistenceReporter.attemptSave(context, operation: "persist context")
    }
}
