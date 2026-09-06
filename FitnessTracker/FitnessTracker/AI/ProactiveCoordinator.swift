import Foundation
import SwiftData
import UserNotifications
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

    func isWeeklyDue() -> Bool { false }
    private func generateWeeklySummary() async {}

    // MARK: - Pattern nudge (#10) — Task 5 fills this

    private func runPatternNudges() async {}

    // MARK: - Check-in reaction (#9) — Task 6 fills this

    func reactToCheckin(_ checkin: DailyCheckinModel) async {}

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
