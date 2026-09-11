import SwiftUI
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics
import LLMKit
import RuleEngine

enum TargetWeightStore {
    static let key = "targetWeightKg"

    static func load(from defaults: UserDefaults = .standard) -> Double? {
        let value = defaults.double(forKey: key)
        return value > 0 ? value : nil
    }

    static func save(_ value: Double?, to defaults: UserDefaults = .standard) {
        defaults.set(value ?? 0, forKey: key)
    }
}

enum HomeSheetType: Identifiable {
    case logWeight
    case targetWeight
    case calendar
    case dailyCheckin
    case weeklySummary
    case dayOverride(Date)
    case workoutDetail(CompletedSessionModel)

    var id: String {
        switch self {
        case .logWeight: return "logWeight"
        case .targetWeight: return "targetWeight"
        case .calendar: return "calendar"
        case .dailyCheckin: return "dailyCheckin"
        case .weeklySummary: return "weeklySummary"
        case .dayOverride(let d): return "dayOverride_\(d.timeIntervalSince1970)"
        case .workoutDetail(let s): return "workoutDetail_\(s.id)"
        }
    }
}

struct HomeView: View {
    @Environment(\.modelContext) private var context
    let profile: UserProfile
    let plan: WeeklyPlan
    let catalog: CatalogStore
    let costSummary: CostSummary
    var onStartSession: (PlannedSession) -> Void
    var onOpenSettings: () -> Void
    var onOpenPlan: () -> Void
    @Binding var reopenDayOverrideDate: Date?
    var onEditExerciseList: (ExerciseLibraryIntent) -> Void

    @Query(sort: \CompletedSessionModel.startedAt, order: .reverse)
    private var completedSessions: [CompletedSessionModel]
    
    @Query(sort: \BodyweightEntryModel.date, order: .reverse)
    private var bodyweightEntries: [BodyweightEntryModel]

    @Query(sort: \DailyCheckinModel.date, order: .reverse)
    private var dailyCheckins: [DailyCheckinModel]

    // Plain @Query + Swift-side filter, not a boolean #Predicate on `confirmed`
    // — the same shape of predicate hung Settings/Root and Settings/Providers
    // by thrashing CoreData's SQL generator (see SessionContainerView.swift's
    // `activeProviderProfile` and docs/HANDOFF.md).
    @Query private var allObservations: [ObservationModel]
    private var pendingObservations: [ObservationModel] {
        allObservations.filter { !$0.confirmed }
    }

    // Same plain @Query + Swift-side filter as `pendingObservations` above —
    // a boolean #Predicate on `resolvedAt == nil` is the exact shape that hung
    // Settings/Root and Settings/Providers earlier this project.
    @Query private var allSuggestions: [PendingCoachSuggestion]
    private var pendingSuggestions: [PendingCoachSuggestion] {
        allSuggestions.filter { $0.resolvedAt == nil }
    }

    @Query(sort: \StoredPlan.generatedAt, order: .reverse) private var plans: [StoredPlan]

    // Most-recent generated weekly recap (Task 4 writes one row per ISO week).
    // Drives the "This week" card, which only appears once a recap exists.
    @Query(sort: \WeeklySummaryModel.weekStartDate, order: .reverse)
    private var weeklySummaries: [WeeklySummaryModel]

    // Same plain @Query + Swift-side filter as `SessionContainerView`'s
    // `activeProviderProfile` — a #Predicate boolean filter here is what hung
    // Settings/Root and Settings/Providers earlier this project.
    @Query private var allProviderProfiles: [ProviderProfile]
    private var activeProviderProfile: ProviderProfile? { allProviderProfiles.first { $0.isActive } }

    // Plain @Query + Swift-side filter for unread coach notes — avoids boolean
    // #Predicate on `readAt == nil` which would hang the app (same shape that
    // hung Settings/Root and Settings/Providers earlier this project).
    @Query(sort: \CoachNoteModel.createdAt, order: .reverse)
    private var allCoachNotes: [CoachNoteModel]
    private var unreadCoachNotes: [CoachNoteModel] {
        allCoachNotes.filter { $0.readAt == nil }
    }
    /// Home gets one current insight preview. The Coach screen remains the
    /// inbox for older daily notes, weekly recaps, check-ins, and pattern nudges.
    private var homeCoachNote: CoachNoteModel? {
        let candidates = unreadCoachNotes.filter { $0.kindRaw != "weekly" }
        // Keep Home focused on one current insight. The Coach screen remains
        // the inbox for older daily notes and other proactive messages.
        return candidates.first(where: { $0.kindRaw == "daily" }) ?? candidates.first
    }
    private var chatProvider: (any LLMProvider)? {
        activeProviderProfile.flatMap {
            try? LLMProviderFactory.make(from: $0, fallback: $0.resolvedFallback(in: allProviderProfiles))
        }
    }

    // Proactive-notification toggles (design spec §7). Same `proactive.settings.*`
    // keys Settings writes and RootView reads; all default on.
    @AppStorage("proactive.settings.daily") private var proactiveDailyOn: Bool = true
    @AppStorage("proactive.settings.weekly") private var proactiveWeeklyOn: Bool = true
    @AppStorage("proactive.settings.inbody") private var proactiveInBodyOn: Bool = true
    @AppStorage("proactive.settings.checkin") private var proactiveCheckinOn: Bool = true
    @AppStorage("proactive.settings.pattern") private var proactivePatternOn: Bool = true
    @AppStorage("gym_reminder_hour") private var reminderHour: Int = 18
    @AppStorage("gym_reminder_minute") private var reminderMinute: Int = 0

    private var proactiveSettings: ProactiveSettings {
        ProactiveSettings(
            dailyOn: proactiveDailyOn, weeklyOn: proactiveWeeklyOn, inbodyOn: proactiveInBodyOn,
            checkinOn: proactiveCheckinOn, patternOn: proactivePatternOn,
            reminderHour: reminderHour, reminderMinute: reminderMinute)
    }

    /// Built the same way `SessionContainerView` builds its coordinators —
    /// active `ProviderProfile` via plain `@Query` + `.first { $0.isActive }`,
    /// provider via `try? LLMProviderFactory.make(from:)`.
    private var proactiveCoordinator: ProactiveCoordinator {
        ProactiveCoordinator(
            context: context, catalog: catalog, provider: chatProvider,
            activeProfile: activeProviderProfile, settings: proactiveSettings)
    }

    @State private var showCoachInbox = false
    @State private var showProfile = false
    /// The collapsed "Coach updates" zone; auto-expands once the user opens it.
    @State private var coachZoneExpanded = false

    @AppStorage("gym_accent_color") private var accentColorKey: String = "lime"
    private var activeAccent: Color { GymTheme.accent(for: accentColorKey) }

    /// The same day→routine map `PlanView` writes (`0`=Monday…`6`=Sunday). The
    /// actual translation and reconciliation live in `WorkoutScheduleStore`.
    @AppStorage("gym_week_schedule_json") private var scheduleJSON: String = ""
    @AppStorage("gym_day_plan_json") private var dayPlanJSON: String = ""
    // The auto-reschedule writes only this key; observing it re-renders the week
    // strip when a missed session moves.
    @AppStorage("gym_day_plan_auto_json") private var autoPlanJSON: String = ""
    private var weekSchedule: [Int: UUID] {
        WorkoutScheduleStore.weekSchedule
    }

    private var dayPlan: [String: String] {
        WorkoutScheduleStore.dayPlan
    }

    private func refreshAutomaticReschedule() {
        let persisted = (try? context.fetch(FetchDescriptor<CompletedSessionModel>())) ?? completedSessions
        WorkoutScheduleStore.refresh(completedSessions: persisted, plan: plan)
    }

    private func effectiveRoutineID(for dayIndex: Int, date: Date) -> UUID? {
        WorkoutScheduleStore.effectiveRoutineID(for: date)
    }

    private func isAutomaticallyRescheduled(dayIndex: Int, date: Date) -> Bool {
        WorkoutScheduleStore.isRescheduled(for: date)
    }

    @State private var weekOffset: Int = 0
    @State private var activeSheet: HomeSheetType?
    // Shared UserDefaults storage keeps Home and Stats in sync and survives
    // view recreation and app relaunches. A value of 0 means no goal is set.
    @AppStorage("targetWeightKg") private var targetWeightKg: Double = 77.0

    init(
        profile: UserProfile,
        plan: WeeklyPlan,
        catalog: CatalogStore,
        costSummary: CostSummary,
        onStartSession: @escaping (PlannedSession) -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenPlan: @escaping () -> Void,
        reopenDayOverrideDate: Binding<Date?> = .constant(nil),
        onEditExerciseList: @escaping (ExerciseLibraryIntent) -> Void = { _ in }
    ) {
        self.profile = profile
        self.plan = plan
        self.catalog = catalog
        self.costSummary = costSummary
        self.onStartSession = onStartSession
        self.onOpenSettings = onOpenSettings
        self.onOpenPlan = onOpenPlan
        self._reopenDayOverrideDate = reopenDayOverrideDate
        self.onEditExerciseList = onEditExerciseList
    }

    private var todaySession: PlannedSession? {
        WorkoutScheduleStore.effectiveSession(for: .now, in: plan)
    }

    /// A finished session that happened today, if any — drives the TODAY row's
    /// completed/not-yet-done state.
    private var todayCompletedSession: CompletedSessionModel? {
        let cal = Calendar.appWeek
        return completedSessions.first { session in
            guard session.finishedAt != nil else { return false }
            return cal.isDateInToday(session.startedAt)
        }
    }

    private var sessionDisplayName: String {
        guard let today = todaySession else { return "Rest day" }
        let name: String
        switch today.order {
        case 0: name = "Push Day"
        case 1: name = "Pull Day"
        case 2: name = "Legs Day"
        default: name = today.focusMuscles.isEmpty ? "Workout" : today.focusMuscles.map(\.label).joined(separator: ", ")
        }
        let cal = Calendar.appWeek
        let now = Date.now
        let monday = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        let dayIndex = cal.dateComponents([.day], from: monday, to: cal.startOfDay(for: now)).day ?? 0
        return isAutomaticallyRescheduled(dayIndex: max(0, min(6, dayIndex)), date: now) ? "\(name) · Rescheduled" : name
    }

    private var currentWeight: Double {
        bodyweightEntries.first?.kg ?? 78.7
    }

    private var todayCheckin: DailyCheckinModel? {
        dailyCheckins.first { Calendar.appWeek.isDate($0.date, inSameDayAs: .now) }
    }

    private var prevWeight: Double? {
        bodyweightEntries.count > 1 ? bodyweightEntries[1].kg : 78.3
    }

    private var weightDelta: Double? {
        guard let prev = prevWeight else { return nil }
        return currentWeight - prev
    }

    @State private var snapshotCache = SessionSnapshotCache()
    private var sessionSnapshots: [CompletedSessionSnapshot] {
        snapshotCache.snapshots(from: completedSessions)
    }

    private var streakSummary: StreakCalculator.Summary {
        let fallback = plan.sessions.count
        let interval = Calendar.appWeek.dateInterval(of: .weekOfYear, for: .now)
        let planned = interval.map { WorkoutScheduleStore.plannedSlotCount(in: $0) } ?? 0
        return StreakCalculator.computeSummary(from: sessionSnapshots, plannedPerWeek: planned > 0 ? planned : fallback, now: .now)
    }

    private var chartPoints: [ChartDataPoint] {
        if !bodyweightEntries.isEmpty {
            return bodyweightEntries.prefix(30).sorted { $0.date < $1.date }.map {
                ChartDataPoint(date: $0.date, value: $0.kg)
            }
        }
        let now = Date()
        return [
            ChartDataPoint(date: now.addingTimeInterval(-45*86400), value: 82.5),
            ChartDataPoint(date: now.addingTimeInterval(-31*86400), value: 80.8),
            ChartDataPoint(date: now.addingTimeInterval(-21*86400), value: 79.9),
            ChartDataPoint(date: now.addingTimeInterval(-11*86400), value: 79.2),
            ChartDataPoint(date: now.addingTimeInterval(-4*86400), value: 78.3),
            ChartDataPoint(date: now, value: currentWeight)
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Keep the primary navigation/header context visible while the
            // dashboard cards scroll beneath it.
            headerSection
                .padding(.bottom, 8)
                .background(GymTheme.bg)
                .zIndex(1)

            ScrollView {
                VStack(spacing: 16) {
                // Today's workout is the reason this screen exists — it leads.
                // Week Strip Card + Nested Today Routine
                weekStripCard

                if todayCheckin == nil {
                    dailyCheckinCard
                }

                // All AI-initiated content (observations, plan suggestions, the
                // coach note preview) collapsed behind one disclosure so the
                // dashboard opens on training state, not inbox noise.
                coachUpdatesCard

                // This-week recap card (only once a WeeklySummaryModel exists)
                if weeklySummaries.first != nil {
                    thisWeekCard
                }

                // Body Weight Card + 30-Day Curve Chart
                bodyWeightCard

                // 1 Week Streak Card
                streakCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 100) // Pad for custom tab bar
            }
        }
        .background(GymTheme.bg.ignoresSafeArea())
        .onAppear {
            refreshAutomaticReschedule()
            reopenDayOverrideIfNeeded()
        }
        .onChange(of: reopenDayOverrideDate) { _, _ in
            reopenDayOverrideIfNeeded()
        }
        .onChange(of: completedSessions.count) { _, _ in
            refreshAutomaticReschedule()
        }
        .onChange(of: scheduleJSON) { _, _ in
            refreshAutomaticReschedule()
        }
        .onChange(of: dayPlanJSON) { _, _ in
            refreshAutomaticReschedule()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .logWeight:
                LogWeightSheet(initialWeight: currentWeight) { newWeight in
                    profile.weightKg = newWeight
                }
            case .targetWeight:
                TargetWeightSheet(
                    targetWeight: targetWeightKg > 0 ? targetWeightKg : nil,
                    // `@AppStorage` writes straight through to the shared
                    // `targetWeightKg` UserDefaults key that `TargetWeightStore`
                    // reads, so no second write is needed here.
                    onSave: { newTarget in targetWeightKg = newTarget },
                    onRemove: { targetWeightKg = 0 }
                )
            case .calendar:
                CalendarSheet(plan: plan, catalog: catalog)
            case .dailyCheckin:
                CheckinEntryView { checkin in
                    Task { await proactiveCoordinator.reactToCheckin(checkin) }
                }
            case .weeklySummary:
                WeeklySummaryView()
            case .dayOverride(let date):
                DayOverrideSheet(date: date, plan: plan, catalog: catalog, onSavedCheckin: { checkin in
                    Task { await proactiveCoordinator.reactToCheckin(checkin) }
                }, onSaveOverride: { override in
                    var updated = WorkoutScheduleStore.userDayPlan
                    let key = Scheduling.isoDateKey(date, calendar: .appWeek)
                    if let override { updated[key] = override } else { updated.removeValue(forKey: key) }
                    WorkoutScheduleStore.saveDayPlan(updated)
                    if let data = try? JSONEncoder().encode(updated), let encoded = String(data: data, encoding: .utf8) {
                        dayPlanJSON = encoded
                    }
                }, onEditExerciseList: { intent in
                    activeSheet = nil
                    onEditExerciseList(intent)
                }) { _ in
                    // The persisted override is the source of truth; the selected session is only the sheet's immediate UI result.
                }
            case .workoutDetail(let session):
                WorkoutDetailSheet(session: session, catalog: catalog, onSavedCheckin: { checkin in
                    Task { await proactiveCoordinator.reactToCheckin(checkin) }
                })
            }
        }
        .sheet(isPresented: $showCoachInbox) {
            CoachInboxView(
                catalog: catalog,
                provider: chatProvider,
                activeProfile: activeProviderProfile,
                onClose: { showCoachInbox = false }
            )
        }
        .fullScreenCover(isPresented: $showProfile) {
            AthleteProfileView(profile: profile, catalog: catalog, onOpenPlan: onOpenPlan)
        }
    }

    private func reopenDayOverrideIfNeeded() {
        guard let date = reopenDayOverrideDate else { return }
        activeSheet = .dayOverride(date)
        reopenDayOverrideDate = nil
    }

    // MARK: - Header Section

    @ViewBuilder
    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image("TrainSageLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text("TrainSage")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(GymTheme.label)
                }

                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.body.weight(.regular))
                    .foregroundStyle(Color(white: 0.65))
            }

            Spacer()

            // Profile keeps athlete-owned inputs reachable without adding a
            // sixth bottom tab or crowding the page with a fourth icon.
            Button {
                Haptics.impactLight()
                showProfile = true
            } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.body)
                    .foregroundStyle(activeAccent)
                    .frame(width: 38, height: 38)
                    .background(GymTheme.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile")
            .accessibilityHint("View and edit your training profile")

            // Coach hub: unread badge opens Insights first; Chat is a separate section.
            Button {
                Haptics.impactLight()
                showCoachInbox = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.body)
                        .foregroundStyle(Color(white: 0.70))
                        .frame(width: 38, height: 38)
                        .background(GymTheme.surface, in: Circle())

                    if unreadCoachNotes.count > 0 {
                        Text(unreadCoachNotes.count > 9 ? "9+" : "\(unreadCoachNotes.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(GymTheme.lime, in: Capsule())
                            .offset(x: 4, y: -4)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Coach insights")
            .accessibilityValue(unreadCoachNotes.isEmpty ? "No unread insights" : "\(unreadCoachNotes.count) unread insights")

            // Settings Button (1-tap opens Settings)
            Button {
                Haptics.impactLight()
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.body)
                    .foregroundStyle(Color(white: 0.70))
                    .frame(width: 38, height: 38)
                    .background(GymTheme.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 4)
        .padding(.top, 12)
    }

    /// Observations, plan suggestions and the coach-note preview collapsed
    /// behind one disclosure, so the dashboard opens on training state.
    /// Nothing pending → the card is absent entirely.
    @ViewBuilder
    private var coachUpdatesCard: some View {
        let pendingCount = pendingObservations.count + pendingSuggestions.count
        if pendingCount > 0 || homeCoachNote != nil {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.snappy(duration: 0.25)) { coachZoneExpanded.toggle() }
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(activeAccent)
                        Text(pendingCount > 0 ? "Coach updates · \(pendingCount) waiting" : "Coach note")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(GymTheme.label)
                        Spacer()
                        Image(systemName: coachZoneExpanded ? "chevron.up" : "chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color(white: 0.60))
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(pendingCount > 0 ? "Coach updates, \(pendingCount) waiting" : "Coach note")
                .accessibilityValue(coachZoneExpanded ? "Expanded" : "Collapsed")

                if coachZoneExpanded {
                    ForEach(pendingObservations) { observation in
                        PendingObservationCard(
                            observation: observation,
                            onAccept: {
                                observation.confirmed = true
                                _ = PersistenceReporter.attemptSave(context, operation: "persist context")
                                if observation.kind == "bodyFatPercent" || observation.kind == "muscleMassKg" {
                                    proactiveCoordinator.resetInBodyReminder()
                                }
                            },
                            onDismiss: {
                                context.delete(observation)
                                _ = PersistenceReporter.attemptSave(context, operation: "persist context")
                            }
                        )
                    }

                    ForEach(pendingSuggestions) { suggestion in
                        SuggestionCard(
                            suggestion: suggestion,
                            catalog: catalog,
                            onAccept: {
                                guard let stored = plans.first else { return }
                                do {
                                    try SuggestionApplier.apply(suggestion, storedPlan: stored, context: context)
                                    try context.save()
                                } catch {
                                    // applier() throws before mutating `suggestion` on
                                    // failure (e.g. its target session ID is stale), so
                                    // `resolvedAt` stays nil and the card simply remains
                                    // for another look instead of vanishing silently.
                                }
                            },
                            onSkip: {
                                SuggestionApplier.skip(suggestion, context: context)
                                _ = PersistenceReporter.attemptSave(context, operation: "persist context")
                            }
                        )
                    }

                    if let note = homeCoachNote {
                        CoachInsightPreview(note: note, onOpenCoach: {
                            showCoachInbox = true
                        })
                    }
                }
            }
            .padding(16)
            .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private var dailyCheckinCard: some View {
        Button {
            activeSheet = .dailyCheckin
        } label: {
            HStack(spacing: 12) {
                Image(systemName: todayCheckin == nil ? "heart.text.square.fill" : "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(todayCheckin == nil ? GymTheme.violet : activeAccent)
                    .frame(width: 42, height: 42)
                    .background((todayCheckin == nil ? GymTheme.violet : activeAccent).opacity(0.15), in: RoundedRectangle(cornerRadius: 13))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(todayCheckin == nil ? "How are you feeling?" : "Today’s check-in")
                        .font(.headline)
                        .foregroundStyle(GymTheme.label)
                    Text(todayCheckin == nil
                         ? "Share sleep and soreness so your coach can adapt."
                         : "Sleep and soreness saved — tap to update.")
                        .font(.subheadline)
                        .foregroundStyle(GymTheme.label2)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(todayCheckin == nil ? "Check in" : "Update")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(activeAccent)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(todayCheckin == nil ? "Daily check-in" : "Update today’s check-in")
    }

    // MARK: - Week Strip Card

    @ViewBuilder
    private var weekStripCard: some View {
        // Establish a SwiftUI dependency on the schedule keys so the dots
        // re-render when the athlete edits an override or the auto-reschedule
        // moves a missed session.
        let _ = scheduleJSON
        let _ = dayPlanJSON
        let _ = autoPlanJSON
        let cal = Calendar.appWeek
        let now = Date()
        let baseMonday = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        let startOfWeek = cal.date(byAdding: .day, value: weekOffset * 7, to: baseMonday) ?? now

        let sessionsByDate = Dictionary(grouping: completedSessions.filter { $0.finishedAt != nil }) {
            cal.startOfDay(for: $0.startedAt)
        }

        VStack(spacing: 14) {
            // Week navigation header
            HStack {
                Button {
                    Haptics.impactLight()
                    weekOffset -= 1
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(GymTheme.label)
                        .frame(width: 30, height: 30)
                        .background(GymTheme.surface2, in: Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    Haptics.impactLight()
                    activeSheet = .calendar
                } label: {
                    HStack(spacing: 5) {
                        Text(weekOffset == 0 ? "This week" : (weekOffset == -1 ? "Last week" : (weekOffset == 1 ? "Next week" : "Week \(weekOffset)")))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(GymTheme.label)
                        Image(systemName: "calendar")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(white: 0.60))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open full calendar")

                Spacer()

                Button {
                    Haptics.impactLight()
                    weekOffset += 1
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(GymTheme.label)
                        .frame(width: 30, height: 30)
                        .background(GymTheme.surface2, in: Circle())
                }
                .buttonStyle(.plain)
            }

            // Clickable weekday circles (MO TU WE TH FR SA SU)
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { dayIndex in
                    let dayDate = cal.date(byAdding: .day, value: dayIndex, to: startOfWeek) ?? startOfWeek
                    let dayNum = cal.component(.day, from: dayDate)
                    let dayName = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"][dayIndex]
                    let isToday = cal.isDateInToday(dayDate)
                    let trainedSessions = sessionsByDate[cal.startOfDay(for: dayDate)] ?? []
                    let isTrained = !trainedSessions.isEmpty
                    let effectiveRoutine = effectiveRoutineID(for: dayIndex, date: dayDate)
                    let isScheduledTrainingDay = effectiveRoutine != nil
                    let isRescheduled = isAutomaticallyRescheduled(dayIndex: dayIndex, date: dayDate)

                    Button {
                        Haptics.impactLight()
                        if let firstTrained = trainedSessions.first {
                            activeSheet = .workoutDetail(firstTrained)
                        } else {
                            activeSheet = .dayOverride(dayDate)
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Text(dayName)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color(white: 0.60))

                            ZStack {
                                if isToday {
                                    Circle()
                                        .fill(activeAccent)
                                        .frame(width: 32, height: 32)
                                    Text("\(dayNum)")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.black)
                                } else {
                                    Text("\(dayNum)")
                                        .font(.system(size: 15, weight: isTrained ? .bold : .medium))
                                        .foregroundStyle(isTrained ? activeAccent : GymTheme.label)
                                }
                            }
                            .frame(height: 32)

                            // Status dot, derived from real state: accent = trained,
                            // orange = an automatic catch-up day, gray = scheduled,
                            // clear = rest day.
                            Circle()
                                .fill(isTrained ? activeAccent : (isRescheduled ? GymTheme.orange : (isScheduledTrainingDay ? Color(white: 0.60) : Color.clear)))
                                .frame(width: 4, height: 4)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(dayName) \(dayNum)")
                    .accessibilityValue(
                        isTrained ? "Completed" :
                        (isRescheduled ? "Rescheduled workout" :
                         (isScheduledTrainingDay ? "Scheduled workout" : "Rest day"))
                    )
                }
            }

            // Nested Today Routine Card (1-tap action) — reads as done/not-done from
            // whether a session actually finished today, not a static label.
            if let today = todaySession {
                let isDoneToday = todayCompletedSession != nil

                Button {
                    Haptics.impactMedium()
                    onStartSession(today)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isDoneToday ? "checkmark" : "figure.strengthtraining.traditional")
                            .font(.title3)
                            .foregroundStyle(.black)
                            .frame(width: 40, height: 40)
                            .background(activeAccent, in: RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(isDoneToday ? "COMPLETED TODAY" : "TODAY")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color(white: 0.60))

                            Text(sessionDisplayName)
                                .font(.body.weight(.bold))
                                .foregroundStyle(GymTheme.label)
                        }

                        Spacer()

                        Text(isDoneToday ? "Redo" : "Start")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(activeAccent)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(activeAccent.opacity(0.16), in: Capsule())
                    }
                    .padding(12)
                    .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - This Week Card

    @ViewBuilder
    private var thisWeekCard: some View {
        if let latest = weeklySummaries.first {
            Button {
                Haptics.impactLight()
                activeSheet = .weeklySummary
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title2)
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                        .background(activeAccent, in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("LAST WEEK")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color(white: 0.60))
                        Text(latest.headline)
                            .font(.body.weight(.bold))
                            .foregroundStyle(GymTheme.label)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(white: 0.60))
                }
                .padding(14)
                .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Body Weight Card

    @ViewBuilder
    private var bodyWeightCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: Body weight | 🎯 77 | + Log
            HStack {
                Text("Body weight")
                    .font(.subheadline.weight(.regular))
                    .foregroundStyle(Color(white: 0.60))

                Spacer()

                // Target weight button
                Button {
                    Haptics.impactLight()
                    activeSheet = .targetWeight
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "target")
                            .font(.footnote.weight(.bold))
                        Text(targetWeightKg > 0 ? String(format: "%.0f", targetWeightKg) : "Goal")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(GymTheme.gold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(GymTheme.surface2, in: Capsule())
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer().frame(width: 8)

                // + Log Button (1-tap opens LogWeightSheet)
                Button {
                    Haptics.impactLight()
                    activeSheet = .logWeight
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                        Text("Log")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(activeAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(activeAccent.opacity(0.16), in: Capsule())
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Weight Value + Delta + Date
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", currentWeight))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(GymTheme.label)

                Text("kg")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color(white: 0.60))

                if let delta = weightDelta {
                    Text("\(delta >= 0 ? "↑" : "↓") \(String(format: "%.1f", abs(delta)))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(delta > 0 ? GymTheme.red : activeAccent)
                }

                Spacer()

                if let latest = bodyweightEntries.first {
                    let cal = Calendar.appWeek
                    let dateStr: String = {
                        if cal.isDateInToday(latest.date) {
                            return "Today"
                        } else if cal.isDateInYesterday(latest.date) {
                            return "Yesterday"
                        } else {
                            return latest.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        }
                    }()
                    Text(dateStr)
                        .font(.subheadline.weight(.regular))
                        .foregroundStyle(Color(white: 0.60))
                }
            }

            // Target Subtitle
            if targetWeightKg > 0 {
                let target = targetWeightKg
                let remaining = currentWeight - target
                HStack(spacing: 6) {
                    Image(systemName: "target")
                        .font(.caption)
                        .foregroundStyle(GymTheme.gold)

                    Text("Goal \(String(format: "%.0f", target)) kg · \(String(format: "%.1f", abs(remaining))) kg to \(remaining >= 0 ? "lose" : "gain")")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(GymTheme.gold)
                }
                .padding(.top, 2)
            }

            // Bezier Curve Chart with Goal Line — themed to the active accent, like
            // Weight trend chart using the app accent palette.
            ProgressLineChart(
                points: chartPoints,
                goal: targetWeightKg > 0 ? targetWeightKg : nil,
                lineColor: activeAccent
            )
            .padding(.top, 4)
        }
        .padding(16)
        .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Streak Card

    @ViewBuilder
    private var streakCard: some View {
        Button {
            Haptics.impactLight()
            activeSheet = .calendar
        } label: {
            HStack(spacing: 14) {
                // Flame Icon
                Image(systemName: "flame.fill")
                    .font(.title)
                    .foregroundStyle(GymTheme.orange)
                    .frame(width: 44, height: 44)
                    .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 10))

                // Streak details
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(streakSummary.currentStreakWeeks) week streak")
                        .font(.body.weight(.bold))
                        .foregroundStyle(GymTheme.label)

                    Text("\(streakSummary.workoutsThisWeek)/\(plan.sessions.count) this week · \(streakSummary.totalWorkouts) workouts total")
                        .font(.footnote.weight(.regular))
                        .foregroundStyle(Color(white: 0.60))
                }

                Spacer()

                // Calendar Action Icon
                Image(systemName: "calendar")
                    .font(.body)
                    .foregroundStyle(Color(white: 0.70))
                    .frame(width: 32, height: 32)
                    .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(14)
            .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
