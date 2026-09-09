//
//  RootView.swift
//  FitnessTracker
//
//  Created by Motiyani, Varun on 28/08/26.
//

import SwiftUI
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics
import LLMKit
import RuleEngine
import UserNotifications
import Combine

/// Bridges a tapped `proactive_weekly` notification into SwiftUI state.
/// `ProactiveCoordinator.scheduleWeekly` stamps the notification's
/// `userInfo["proactive"] == "weekly"`; tapping it flips `showWeeklySummary`,
/// which `RootView` observes to present `WeeklySummaryView` as a sheet.
@MainActor
final class NotificationResponder: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var showWeeklySummary = false

    /// Show the banner even with the app foregrounded for proactive
    /// notifications only, so the tap path is reachable while the user is
    /// in-app (and testable on the simulator). Other notifications keep iOS's
    /// default foreground behaviour (suppressed).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let isProactive = notification.request.content.userInfo["proactive"] != nil
        completionHandler(isProactive ? [.banner, .sound] : [])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let isWeekly = response.notification.request.content.userInfo["proactive"] as? String == "weekly"
        completionHandler()
        if isWeekly {
            Task { @MainActor in self.showWeeklySummary = true }
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var profiles: [UserProfile]
    @Query(sort: \StoredPlan.generatedAt, order: .reverse) private var plans: [StoredPlan]
    @Query private var allProviderProfiles: [ProviderProfile]
    private var activeProfiles: [ProviderProfile] { allProviderProfiles.filter(\.isActive) }
    @Query(sort: \AICallRecord.timestamp) private var calls: [AICallRecord]
    @Query private var completedSessions: [CompletedSessionModel]

    @State private var catalog: CatalogStore?
    @State private var loadFailed = false
    @State private var lastNote: String?
    @State private var isGenerating = false

    // openGym 5-tab navigation state
    @State private var selectedTab: AppTab = .home
    @State private var activePlannedSession: PlannedSession?
    @State private var showSettings = false
    @State private var exerciseLibraryIntent: ExerciseLibraryIntent?
    @State private var reopenDayOverrideDate: Date?

    // Presents WeeklySummaryView when a `proactive_weekly` notification is tapped.
    // The instance is owned by `AppDelegate` (which installs it as the
    // `UNUserNotificationCenter` delegate during launch) and injected via the environment.
    @EnvironmentObject private var notificationResponder: NotificationResponder

    // Per-type proactive-notification toggles (Settings owns the UI; default on).
    @AppStorage("proactive.settings.daily") private var proactiveDailyOn: Bool = true
    @AppStorage("proactive.settings.weekly") private var proactiveWeeklyOn: Bool = true
    @AppStorage("proactive.settings.inbody") private var proactiveInBodyOn: Bool = true
    @AppStorage("proactive.settings.checkin") private var proactiveCheckinOn: Bool = true
    @AppStorage("proactive.settings.pattern") private var proactivePatternOn: Bool = true
    @AppStorage("gym_reminder_hour") private var reminderHour: Int = 18
    @AppStorage("gym_reminder_minute") private var reminderMinute: Int = 0

    private var summary: CostSummary {
        CostSummary.from(records: calls.map { .init(timestamp: $0.timestamp, costUSD: $0.costUSD) },
                         now: .now)
    }

    /// Resolved the same way `SessionContainerView`/`generateAndStore` do —
    /// `try? LLMProviderFactory.make(from:)` off the active `ProviderProfile`
    /// — kept in one place here rather than duplicated a third time.
    private var resolvedProvider: (any LLMProvider)? {
        guard let activeProfile = activeProfiles.first else { return nil }
        return try? LLMProviderFactory.make(
            from: activeProfile,
            fallback: activeProfile.resolvedFallback(in: allProviderProfiles))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // openGym Custom Bottom Navigation Bar (Persistent across all views & Settings)
            if profiles.first != nil, let plan = try? plans.first?.decodedPlan() {
                CustomTabBar(
                    selectedTab: $selectedTab,
                    isWorkoutActive: activePlannedSession != nil,
                    onStartPressed: {
                        if let session = WorkoutScheduleStore.effectiveSession(for: .now, in: plan)
                            ?? plan.sessions.sorted(by: { $0.order < $1.order }).first {
                            activePlannedSession = session
                        }
                    }
                )
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $activePlannedSession) { session in
            if let catalog {
                SessionContainerView(planned: session, catalog: catalog) {
                    activePlannedSession = nil
                }
            }
        }
        .sheet(isPresented: $notificationResponder.showWeeklySummary) {
            WeeklySummaryView()
        }
        .onChange(of: selectedTab) { _, _ in
            if showSettings {
                showSettings = false
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, let catalog else { return }
            WorkoutScheduleStore.refresh(completedSessions: completedSessions)
            runProactive(catalog: catalog)
        }
        .overlay(alignment: .top) {
            if let lastNote {
                Text(lastNote)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .center) {
            if isGenerating {
                ProgressView("Updating your plan…")
                    .padding()
                    .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .animation(.default, value: lastNote)
        .animation(.default, value: isGenerating)
        .task(id: lastNote) {
            guard lastNote != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            lastNote = nil
        }
        .task {
            SessionRunner.resolveAbandoned(in: context, now: .now)
            WorkoutScheduleStore.refresh(completedSessions: completedSessions)
            if catalog == nil {
                do { catalog = try BundledCatalog.load() }
                catch { loadFailed = true }
            }
            if profiles.isEmpty, let catalog {
                let defaultProfile = UserProfile(
                    goalRaw: "buildMuscle",
                    experienceRaw: "intermediate",
                    heightCm: 178,
                    weightKg: 75,
                    birthYear: 2000,
                    sexRaw: "male",
                    sessionsPerWeek: 4,
                    sessionLengthMinutes: 60,
                    availableEquipmentRaws: ["barbell", "dumbbell", "cable", "machine", "bodyweight"],
                    excludedMuscleRaws: [],
                    excludedExerciseIDs: []
                )
                context.insert(defaultProfile)
                DemoSeedGenerator.seedDemoHistory(into: context, catalog: catalog)
                let userContext = defaultProfile.makeUserContext()
                _ = await generateAndStore(context: userContext,
                                           activeProfile: nil,
                                           catalog: catalog,
                                           modelContext: context)
            }
            if let catalog {
                runProactive(catalog: catalog)
            }
        }
    }

    /// Builds a `ProactiveCoordinator` from the current Settings toggles and
    /// resolved provider, then fires its due-checks pass without blocking.
    /// Safe to call repeatedly — the coordinator's `UserDefaults` day/week
    /// keys make every LLM-backed item idempotent per period.
    private func runProactive(catalog: CatalogStore) {
        let settings = ProactiveSettings(
            dailyOn: proactiveDailyOn,
            weeklyOn: proactiveWeeklyOn,
            inbodyOn: proactiveInBodyOn,
            checkinOn: proactiveCheckinOn,
            patternOn: proactivePatternOn,
            reminderHour: reminderHour,
            reminderMinute: reminderMinute
        )
        let coordinator = ProactiveCoordinator(
            context: context,
            catalog: catalog,
            provider: resolvedProvider,
            activeProfile: activeProfiles.first,
            settings: settings
        )
        Task {
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            if status == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            await coordinator.runDueChecks()
        }
    }

    @ViewBuilder
    private var content: some View {
        if loadFailed {
            ContentUnavailableView("Couldn't load the exercise catalog",
                                   systemImage: "exclamationmark.triangle")
        } else if showSettings {
            // Settings rendered inline to preserve persistent bottom CustomTabBar
            NavigationStack {
                SettingsView(onClose: { showSettings = false })
            }
        } else if let profile = profiles.first, let plan = try? plans.first?.decodedPlan(), let catalog {
            Group {
                switch selectedTab {
                case .home:
                    HomeView(
                        profile: profile,
                        plan: plan,
                        catalog: catalog,
                        costSummary: summary,
                        onStartSession: { session in activePlannedSession = session },
                        onOpenSettings: { showSettings = true },
                        onOpenPlan: { selectedTab = .plan },
                        reopenDayOverrideDate: $reopenDayOverrideDate,
                        onEditExerciseList: { intent in
                            reopenDayOverrideDate = intent.date
                            exerciseLibraryIntent = intent
                            selectedTab = .exercises
                        }
                    )
                case .plan:
                    PlanView(
                        plan: plan,
                        catalog: catalog,
                        onStartSession: { session in activePlannedSession = session },
                        onSplitChanged: { template in
                            profile.splitTemplateName = template.name
                            profile.sessionsPerWeek = template.sessionCount
                            profile.updatedAt = .now
                            try? context.save()
                            regeneratePlan(for: profile)
                        }
                    )
                case .start:
                    WorkoutTabView(
                        plan: plan,
                        catalog: catalog,
                        onStartSession: { session in activePlannedSession = session }
                    )
                case .stats:
                    StatsView(
                        plan: plan,
                        catalog: catalog
                    )
                case .exercises:
                    LibraryView(
                        catalog: catalog,
                        plan: plan,
                        exerciseLibraryIntent: $exerciseLibraryIntent,
                        onWorkoutSelectionCommitted: { date in
                            reopenDayOverrideDate = date
                            selectedTab = .home
                        }
                    )
                case .coach:
                    ChatView(catalog: catalog, provider: resolvedProvider, activeProfile: activeProfiles.first)
                }
            }
        } else if profiles.isEmpty {
            OnboardingView { profile in
                context.insert(profile)
                regeneratePlan(for: profile)
            }
        } else {
            ProgressView()
        }
    }

    private func regeneratePlan(for profile: UserProfile) {
        guard let catalog, !isGenerating else { return }
        let userContext = profile.makeUserContext()
        let activeProfile = activeProfiles.first
        isGenerating = true
        Task {
            defer { isGenerating = false }
            let outcome = await generateAndStore(context: userContext,
                                                 activeProfile: activeProfile,
                                                 catalog: catalog,
                                                 modelContext: context)
            lastNote = outcome.note
        }
    }
}
