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

/// Startup persistence checks must query SwiftData directly. `@Query` can be
/// temporarily empty while its first fetch is still being delivered to the
/// view, which used to make the bootstrap path seed a new default profile on
/// every relaunch and overwrite the user's choices.
@MainActor
enum AppBootstrap {
    static func existingUserProfile(in context: ModelContext) -> UserProfile? {
        var descriptor = FetchDescriptor<UserProfile>()
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func needsInitialSeed(in context: ModelContext) -> Bool {
        do {
            var descriptor = FetchDescriptor<UserProfile>()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).isEmpty
        } catch {
            // A fetch failure is not proof that the store is empty. Failing
            // closed prevents a transient SwiftData error from replacing the
            // user's profile with defaults.
            return false
        }
    }
}

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
    @Query(sort: \CustomExerciseModel.name) private var customExercises: [CustomExerciseModel]

    @State private var catalog: CatalogStore?
    /// Memoized `catalog` + custom exercises. Rebuilt only when the bundled
    /// catalog loads or a custom exercise is added/edited/removed — never on a
    /// plain `body` re-evaluation. Reconstructing the ~1.5 MB catalog (full
    /// struct-array copy + dictionary build) on every render was freezing the
    /// main thread on each tab tap.
    @State private var mergedCatalogCache = MergedCatalogCache()
    @State private var loadFailed = false
    @State private var lastNote: String?
    @State private var isGenerating = false

    // Main five-tab navigation state
    @State private var selectedTab: AppTab = .home

    init() {
        // The app draws its own floating glass `CustomTabBar`; make the system
        // `UITabBar` fully invisible so its iOS 26 glass background doesn't show
        // as a second bar behind ours. `.toolbar(.hidden, for: .tabBar)` hides
        // the items but can leave the material/hairline behind.
        let clear = UITabBarAppearance()
        clear.configureWithTransparentBackground()
        clear.backgroundColor = .clear
        clear.shadowColor = .clear
        UITabBar.appearance().standardAppearance = clear
        UITabBar.appearance().scrollEdgeAppearance = clear
        UITabBar.appearance().isHidden = true
    }
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

    private var effectiveCatalog: CatalogStore? {
        guard let catalog else { return nil }
        return mergedCatalogCache.catalog(base: catalog, custom: customExercises)
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

            // Persistent custom bottom navigation bar across views and Settings
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
            if let catalog = effectiveCatalog {
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
            WorkoutScheduleStore.refresh(completedSessions: persistedCompletedSessions())
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
            WorkoutScheduleStore.refresh(completedSessions: persistedCompletedSessions())
            if catalog == nil {
                do { catalog = try BundledCatalog.load() }
                catch { loadFailed = true }
            }
            // Do not use `profiles.isEmpty` here. `@Query` may report an empty
            // snapshot before SwiftData has finished its initial fetch, which
            // caused the default profile/plan to be seeded again on relaunch.
            if AppBootstrap.needsInitialSeed(in: context), let catalog {
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
        } else if let profile = profiles.first, let plan = try? plans.first?.decodedPlan(), let catalog = effectiveCatalog {
            // `TabView` keeps every tab mounted, so switching is a visibility
            // toggle (instant) rather than a teardown + rebuild. Each screen's
            // heavy computes are memoized so the one-time build on first visit
            // stays cheap and off-screen graph updates are light.
            TabView(selection: $selectedTab) {
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
                .tag(AppTab.home)

                PlanView(
                    plan: plan,
                    catalog: catalog,
                    onStartSession: { session in activePlannedSession = session },
                    onSplitChanged: { template in
                        profile.splitTemplateName = template.name
                        profile.sessionsPerWeek = template.sessionCount
                        profile.updatedAt = .now
                        _ = PersistenceReporter.attemptSave(context, operation: "persist context")
                        regeneratePlan(for: profile)
                    }
                )
                .tag(AppTab.plan)

                WorkoutTabView(
                    plan: plan,
                    catalog: catalog,
                    onStartSession: { session in activePlannedSession = session }
                )
                .tag(AppTab.start)

                StatsView(plan: plan, catalog: catalog)
                    .tag(AppTab.stats)

                LibraryView(
                    catalog: catalog,
                    plan: plan,
                    exerciseLibraryIntent: $exerciseLibraryIntent,
                    onWorkoutSelectionCommitted: { date in
                        reopenDayOverrideDate = date
                        selectedTab = .home
                    }
                )
                .tag(AppTab.exercises)

                // Built only while selected — `resolvedProvider` reads the
                // Keychain and spins a URLSession; no need on every body pass.
                Group {
                    if selectedTab == .coach {
                        ChatView(catalog: catalog, provider: resolvedProvider, activeProfile: activeProfiles.first)
                    } else {
                        Color.clear
                    }
                }
                .tag(AppTab.coach)
            }
            .toolbar(.hidden, for: .tabBar)
        } else if AppBootstrap.needsInitialSeed(in: context) {
            // Direct fetch, not `profiles.isEmpty`: `@Query` can report an empty
            // first snapshot on relaunch before SwiftData hydrates, which would
            // briefly flash onboarding over existing data.
            OnboardingView { profile in
                context.insert(profile)
                do {
                    // Persist the profile before any async AI/rule-engine work.
                    // If generation is interrupted, the athlete's answers are
                    // still present on the next launch.
                    try context.save()
                    regeneratePlan(for: profile)
                } catch {
                    lastNote = "Could not save your profile: \(error.localizedDescription)"
                }
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

    /// `@Query` is allowed to render an empty first snapshot while SwiftData
    /// hydrates. Scheduling must never use that transient snapshot because it
    /// could rewrite the persisted catch-up layer as if no workouts existed.
    private func persistedCompletedSessions() -> [CompletedSessionModel] {
        (try? context.fetch(FetchDescriptor<CompletedSessionModel>())) ?? []
    }
}
