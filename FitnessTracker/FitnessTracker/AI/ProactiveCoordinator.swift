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

nonisolated struct ProactiveSettings: Sendable {
    var dailyOn: Bool
    var weeklyOn: Bool
    var inbodyOn: Bool
    var checkinOn: Bool
    var patternOn: Bool
    var reminderHour: Int
    var reminderMinute: Int
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
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.calendar = .isoUTC; return f
    }()

    func runDueChecks() async {
        if settings.inbodyOn { scheduleInBodyReminderIfNeeded() }
        else { notificationCenter.removePendingNotificationRequests(withIdentifiers: ["proactive_inbody"]) }

        guard provider != nil else { return }

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
            context.insert(CoachNoteModel(kindRaw: "daily", text: text))
            try? context.save()
            scheduleDaily(body: text)
            UserDefaults.standard.set(Self.dayFormatter.string(from: .now), forKey: "proactive.daily.lastGeneratedDay")
        } catch ToolLoopError.exceededMaxIterations(let calls) {
            recordCalls(calls, callType: "dailyNarration")
        } catch { return }
    }

    private func scheduleDaily(body: String) {
        let content = UNMutableNotificationContent()
        content.title = "From your coach"
        content.body = body
        content.sound = .default
        var dc = DateComponents(); dc.hour = settings.reminderHour; dc.minute = settings.reminderMinute
        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ["proactive_daily"])
        notificationCenter.add(UNNotificationRequest(identifier: "proactive_daily", content: content, trigger: trigger))
    }

    // MARK: - InBody reminder (#8) — no LLM

    private func scheduleInBodyReminderIfNeeded() {
        notificationCenter.getPendingNotificationRequests { requests in
            guard !requests.contains(where: { $0.identifier == "proactive_inbody" }) else { return }
            let content = UNMutableNotificationContent()
            content.title = "InBody scan due"
            content.body = "It's been about 5 weeks — take a scan and tell your coach the numbers in chat."
            content.sound = .default
            let fiveWeeks: TimeInterval = 5 * 7 * 24 * 3600
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fiveWeeks, repeats: true)
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "proactive_inbody", content: content, trigger: trigger))
        }
    }

    /// Call when a body-composition observation is confirmed so the 5-week
    /// clock restarts. (Wired in a later task / by ObservationModel confirm UI.)
    func resetInBodyReminder() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ["proactive_inbody"])
        if settings.inbodyOn { scheduleInBodyReminderIfNeeded() }
    }

    // MARK: - Weekly (#7) — Task 4 fills this

    func isWeeklyDue() -> Bool {
        guard let weekStart = Calendar.isoUTC.dateInterval(of: .weekOfYear, for: .now)?.start else { return false }
        let iso = ISO8601DateFormatter().string(from: weekStart)
        return UserDefaults.standard.string(forKey: "proactive.weekly.lastWeekStart") != iso
    }

    private func generateWeeklySummary() async {
        guard let provider,
              let weekStart = Calendar.isoUTC.dateInterval(of: .weekOfYear, for: .now)?.start else { return }
        let priorWeek = Calendar.isoUTC.date(byAdding: .weekOfYear, value: -1, to: weekStart)!
        let priorInterval = DateInterval(start: priorWeek, end: weekStart)

        let allSessions = (try? context.fetch(FetchDescriptor<CompletedSessionModel>())) ?? []
        let weekSessions = allSessions.filter { $0.finishedAt.map(priorInterval.contains) ?? false }
        let snapshots = allSessions.map { $0.toSnapshot() }
        let plannedPerWeek = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first?.sessionsPerWeek ?? 3
        let streak = StreakCalculator.computeSummary(from: snapshots, plannedPerWeek: plannedPerWeek).currentStreakWeeks
        let prCount = ((try? context.fetch(FetchDescriptor<PersonalRecordModel>())) ?? [])
            .filter { priorInterval.contains($0.date) }.count

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

            // One row per week — overwrite an existing row for the same weekStart.
            let existing = ((try? context.fetch(FetchDescriptor<WeeklySummaryModel>())) ?? [])
                .first { Calendar.isoUTC.isDate($0.weekStartDate, inSameDayAs: weekStart) }
            if let existing {
                existing.headline = dto.headline
                existing.summaryBody = dto.body
                existing.nextWeekFocus = dto.nextWeekFocus
                existing.generatedAt = .now
            } else {
                context.insert(WeeklySummaryModel(weekStartDate: weekStart, headline: dto.headline,
                    summaryBody: dto.body, nextWeekFocus: dto.nextWeekFocus))
            }
            context.insert(CoachNoteModel(kindRaw: "weekly", text: dto.headline))
            try? context.save()
            scheduleWeekly(body: dto.headline)
            UserDefaults.standard.set(ISO8601DateFormatter().string(from: weekStart),
                                     forKey: "proactive.weekly.lastWeekStart")
        } catch ToolLoopError.exceededMaxIterations(let calls) {
            recordCalls(calls, callType: "weeklySummary")
        } catch { return }
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

    private func runPatternNudges() async {
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
            context.insert(CoachNoteModel(kindRaw: "pattern", text: result.value.nudge))
            try? context.save()
            UserDefaults.standard.set(ISO8601DateFormatter().string(from: .now),
                                      forKey: "proactive.patternNudge.\(target.id.uuidString)")
        } catch ToolLoopError.exceededMaxIterations(let calls) {
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
            context.insert(CoachNoteModel(kindRaw: "checkin", text: text))
            try? context.save()

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
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2 * 3600, repeats: false)
                notificationCenter.removePendingNotificationRequests(withIdentifiers: ["proactive_checkin"])
                notificationCenter.add(UNNotificationRequest(identifier: "proactive_checkin", content: content, trigger: trigger),
                                       withCompletionHandler: nil)
            }
        } catch ToolLoopError.exceededMaxIterations(let calls) {
            recordCalls(calls, callType: "checkinReaction")
        } catch { return }
    }

    // MARK: - Shared helpers

    private func mostRecentPlan() -> WeeklyPlan? {
        (try? context.fetch(FetchDescriptor<StoredPlan>(sortBy: [SortDescriptor(\.generatedAt, order: .reverse)])))?
            .first.flatMap { try? $0.decodedPlan() }
    }

    /// Today's planned session if it hasn't been completed yet, else the next
    /// not-yet-completed one in `order`.
    private func todaysOrNextSession(in plan: WeeklyPlan) -> PlannedSession? {
        let started = Set(((try? context.fetch(FetchDescriptor<CompletedSessionModel>())) ?? [])
            .compactMap(\.plannedSessionID))
        return plan.sessions.sorted { $0.order < $1.order }.first { !started.contains($0.id) }
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
                success: call.succeeded, usedFallback: false))
        }
        try? context.save()
    }
}
