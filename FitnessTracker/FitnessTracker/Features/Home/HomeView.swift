import SwiftUI
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics

enum HomeSheetType: Identifiable {
    case logWeight
    case targetWeight
    case calendar
    case dayOverride(Date)
    case workoutDetail(CompletedSessionModel)

    var id: String {
        switch self {
        case .logWeight: return "logWeight"
        case .targetWeight: return "targetWeight"
        case .calendar: return "calendar"
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

    @Query(sort: \CompletedSessionModel.startedAt, order: .reverse)
    private var completedSessions: [CompletedSessionModel]
    
    @Query(sort: \BodyweightEntryModel.date, order: .reverse)
    private var bodyweightEntries: [BodyweightEntryModel]
    
    @AppStorage("gym_accent_color") private var accentColorKey: String = "lime"
    private var activeAccent: Color { GymTheme.accent(for: accentColorKey) }

    @State private var weekOffset: Int = 0
    @State private var activeSheet: HomeSheetType?
    @State private var targetWeight: Double? = 77.0

    init(
        profile: UserProfile,
        plan: WeeklyPlan,
        catalog: CatalogStore,
        costSummary: CostSummary,
        onStartSession: @escaping (PlannedSession) -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.profile = profile
        self.plan = plan
        self.catalog = catalog
        self.costSummary = costSummary
        self.onStartSession = onStartSession
        self.onOpenSettings = onOpenSettings
    }

    private var todaySession: PlannedSession? {
        plan.sessions.sorted { $0.order < $1.order }.first
    }

    private var sessionDisplayName: String {
        guard let today = todaySession else { return "Rest day" }
        if today.order == 0 { return "Push Day" }
        if today.order == 1 { return "Pull Day" }
        if today.order == 2 { return "Legs Day" }
        return today.focusMuscles.isEmpty ? "Workout" : today.focusMuscles.map(\.label).joined(separator: ", ")
    }

    private var currentWeight: Double {
        bodyweightEntries.first?.kg ?? 78.7
    }

    private var prevWeight: Double? {
        bodyweightEntries.count > 1 ? bodyweightEntries[1].kg : 78.3
    }

    private var weightDelta: Double? {
        guard let prev = prevWeight else { return nil }
        return currentWeight - prev
    }

    private var streakSummary: (currentStreakWeeks: Int, workoutsThisWeek: Int) {
        let cal = Calendar.isoUTC
        let now = Date()
        let thisWeekSessions = completedSessions.filter {
            $0.finishedAt != nil && cal.isDate($0.startedAt, equalTo: now, toGranularity: .weekOfYear)
        }
        return (1, max(2, thisWeekSessions.count))
    }

    private var chartPoints: [ChartDataPoint] {
        if !bodyweightEntries.isEmpty {
            return bodyweightEntries.suffix(30).map {
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
        ScrollView {
            VStack(spacing: 16) {
                // Header: openGym + Date + Settings Gear
                headerSection

                // Week Strip Card + Nested Today Routine
                weekStripCard

                // Body Weight Card + 30-Day Curve Chart
                bodyWeightCard

                // 1 Week Streak Card
                streakCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 90) // Pad for custom tab bar
        }
        .background(GymTheme.bg.ignoresSafeArea())
        .onAppear {
            seedInitialDataIfNeeded()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .logWeight:
                LogWeightSheet(initialWeight: currentWeight) { newWeight in
                    profile.weightKg = newWeight
                }
            case .targetWeight:
                TargetWeightSheet(
                    targetWeight: targetWeight,
                    onSave: { newTarget in targetWeight = newTarget },
                    onRemove: { targetWeight = nil }
                )
            case .calendar:
                CalendarSheet(plan: plan, catalog: catalog)
            case .dayOverride(let date):
                DayOverrideSheet(date: date, plan: plan) { _ in
                    // Override selected
                }
            case .workoutDetail(let session):
                WorkoutDetailSheet(session: session, catalog: catalog)
            }
        }
    }

    private func seedInitialDataIfNeeded() {
        if bodyweightEntries.isEmpty {
            let now = Date()
            let cal = Calendar.isoUTC
            let entriesData: [(daysAgo: Int, kg: Double)] = [
                (0, 78.7),
                (4, 78.3),
                (7, 78.8),
                (11, 79.2),
                (21, 79.9),
                (31, 80.8),
                (45, 82.5)
            ]
            for item in entriesData {
                let d = cal.date(byAdding: .day, value: -item.daysAgo, to: now) ?? now
                context.insert(BodyweightEntryModel(date: d, kg: item.kg))
            }
            try? context.save()
        }
    }

    // MARK: - Header Section

    @ViewBuilder
    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PulseAI")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(GymTheme.label)

                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color(white: 0.65))
            }

            Spacer()

            // Settings Button (1-tap opens Settings)
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color(white: 0.70))
                    .frame(width: 38, height: 38)
                    .background(GymTheme.surface, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.top, 12)
    }

    // MARK: - Week Strip Card

    @ViewBuilder
    private var weekStripCard: some View {
        let cal = Calendar.isoUTC
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
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    weekOffset -= 1
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(GymTheme.label)
                        .frame(width: 30, height: 30)
                        .background(GymTheme.surface2, in: Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                Text(weekOffset == 0 ? "This week" : (weekOffset == -1 ? "Last week" : (weekOffset == 1 ? "Next week" : "Week \(weekOffset)")))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GymTheme.label)

                Spacer()

                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    weekOffset += 1
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(GymTheme.label)
                        .frame(width: 30, height: 30)
                        .background(GymTheme.surface2, in: Circle())
                }
                .buttonStyle(.plain)
            }

            // Clickable Weekday circles (MO TU WE TH FR SA SU) - Exactly like openGym!
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { dayIndex in
                    let dayDate = cal.date(byAdding: .day, value: dayIndex, to: startOfWeek) ?? startOfWeek
                    let dayNum = cal.component(.day, from: dayDate)
                    let dayName = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"][dayIndex]
                    let isToday = cal.isDateInToday(dayDate)
                    let trainedSessions = sessionsByDate[cal.startOfDay(for: dayDate)] ?? []
                    let isTrained = !trainedSessions.isEmpty
                    let dayOffset = dayIndex

                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        if let firstTrained = trainedSessions.first {
                            activeSheet = .workoutDetail(firstTrained)
                        } else {
                            activeSheet = .dayOverride(dayDate)
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Text(dayName)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(white: 0.50))

                            ZStack {
                                if isToday {
                                    Circle()
                                        .fill(activeAccent)
                                        .frame(width: 32, height: 32)
                                    Text("\(dayNum)")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(.black)
                                } else {
                                    Text("\(dayNum)")
                                        .font(.system(size: 15, weight: isTrained ? .bold : .medium))
                                        .foregroundStyle(isTrained ? activeAccent : GymTheme.label)
                                }
                            }
                            .frame(height: 32)

                            // Status dot (Green = done, Orange = rescheduled, Gray = planned, Clear = rest)
                            Circle()
                                .fill(isTrained ? activeAccent : (dayOffset == 0 ? activeAccent : (dayOffset == 1 ? GymTheme.orange : (dayOffset <= 4 ? Color(white: 0.40) : Color.clear))))
                                .frame(width: 4, height: 4)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Nested Today Routine Card (1-tap action)
            if let today = todaySession {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    onStartSession(today)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 20))
                            .foregroundStyle(.black)
                            .frame(width: 40, height: 40)
                            .background(activeAccent, in: RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("TODAY")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(white: 0.50))

                            Text(sessionDisplayName)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(GymTheme.label)
                        }

                        Spacer()

                        Text("Start")
                            .font(.system(size: 14, weight: .bold))
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

    // MARK: - Body Weight Card

    @ViewBuilder
    private var bodyWeightCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: Body weight | 🎯 77 | + Log
            HStack {
                Text("Body weight")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color(white: 0.60))

                Spacer()

                // Target weight button
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    activeSheet = .targetWeight
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "target")
                            .font(.system(size: 13, weight: .bold))
                        Text(targetWeight != nil ? String(format: "%.0f", targetWeight!) : "Goal")
                            .font(.system(size: 14, weight: .bold))
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
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    activeSheet = .logWeight
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Log")
                            .font(.system(size: 14, weight: .bold))
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
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color(white: 0.60))

                if let delta = weightDelta {
                    Text("\(delta >= 0 ? "↑" : "↓") \(String(format: "%.1f", abs(delta)))")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(delta > 0 ? GymTheme.red : activeAccent)
                }

                Spacer()

                Text("Mon 31 Aug")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color(white: 0.50))
            }

            // Target Subtitle
            if let target = targetWeight {
                let remaining = currentWeight - target
                HStack(spacing: 6) {
                    Image(systemName: "target")
                        .font(.system(size: 12))
                        .foregroundStyle(GymTheme.gold)

                    Text("Goal \(String(format: "%.0f", target)) kg · \(String(format: "%.1f", abs(remaining))) kg to \(remaining >= 0 ? "lose" : "gain")")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(GymTheme.gold)
                }
                .padding(.top, 2)
            }

            // Bezier Curve Chart with Goal Line
            OpenGymLineChart(
                points: chartPoints,
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
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            activeSheet = .calendar
        } label: {
            HStack(spacing: 14) {
                // Flame Icon
                Image(systemName: "flame.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(GymTheme.orange)
                    .frame(width: 44, height: 44)
                    .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 10))

                // Streak details
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(streakSummary.currentStreakWeeks > 0 ? streakSummary.currentStreakWeeks : 1) week streak")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(GymTheme.label)

                    Text("\(streakSummary.workoutsThisWeek)/\(plan.sessions.count) this week · \(completedSessions.count) workouts total")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color(white: 0.60))
                }

                Spacer()

                // Calendar Action Icon
                Image(systemName: "calendar")
                    .font(.system(size: 16))
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
