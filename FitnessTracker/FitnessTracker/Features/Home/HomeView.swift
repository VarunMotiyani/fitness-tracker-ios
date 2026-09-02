import SwiftUI
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics

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

    @State private var weekOffset: Int = 0
    @State private var showLogBw = false
    @State private var showTargetBw = false
    @State private var showCalendar = false
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

    private var streakSummary: StreakCalculator.Summary {
        let snapshots = completedSessions.map { $0.toSnapshot() }
        let plannedCount = plan.sessions.count
        return StreakCalculator.computeSummary(from: snapshots, plannedPerWeek: plannedCount, now: .now)
    }

    private var chartPoints: [ChartDataPoint] {
        let entries = bodyweightEntries.reversed()
        if entries.count >= 2 {
            return entries.map { ChartDataPoint(date: $0.date, value: $0.kg) }
        }
        let now = Date()
        return [
            ChartDataPoint(date: now.addingTimeInterval(-60*86400), value: 82.5),
            ChartDataPoint(date: now.addingTimeInterval(-48*86400), value: 81.9),
            ChartDataPoint(date: now.addingTimeInterval(-38*86400), value: 81.2),
            ChartDataPoint(date: now.addingTimeInterval(-30*86400), value: 80.8),
            ChartDataPoint(date: now.addingTimeInterval(-20*86400), value: 79.9),
            ChartDataPoint(date: now.addingTimeInterval(-10*86400), value: 79.2),
            ChartDataPoint(date: now.addingTimeInterval(-2*86400), value: 78.3),
            ChartDataPoint(date: now, value: currentWeight)
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header (openGym title + date + settings gear)
                headerView

                // Card 1: Week Strip + Nested Today Workout
                weekAndTodayCard

                // Card 2: Body Weight with Goal & Gradient Sparkline Chart
                bodyWeightCard

                // Card 3: Streak Card with Live Computation & Calendar Action
                streakCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 90)
        }
        .background(GymTheme.bg.ignoresSafeArea())
        .sheet(isPresented: $showLogBw) {
            LogWeightSheet(initialWeight: currentWeight) { newWeight in
                profile.weightKg = newWeight
            }
        }
        .sheet(isPresented: $showTargetBw) {
            TargetWeightSheet(
                targetWeight: targetWeight,
                onSave: { newTarget in targetWeight = newTarget },
                onRemove: { targetWeight = nil }
            )
        }
        .sheet(isPresented: $showCalendar) {
            CalendarSheet(plan: plan, catalog: catalog)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerView: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("openGym")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(GymTheme.label)
                Text("Wednesday 2 September")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color(white: 0.60))
            }
            Spacer()
            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(white: 0.85))
                    .frame(width: 36, height: 36)
                    .background(GymTheme.surface2, in: Circle())
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Week and Today Card

    @ViewBuilder
    private var weekAndTodayCard: some View {
        let cal = Calendar.isoUTC
        let today = Date()
        let startOfWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today
        let adjustedStart = cal.date(byAdding: .weekOfYear, value: weekOffset, to: startOfWeek) ?? startOfWeek
        let dayLabels = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

        VStack(spacing: 14) {
            // Week header with chevrons
            HStack {
                Button { weekOffset -= 1 } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(white: 0.60))
                }
                Spacer()
                Text("This week")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(white: 0.60))
                Spacer()
                Button { weekOffset += 1 } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(white: 0.60))
                }
            }
            .padding(.horizontal, 8)

            // 7 Day columns
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { dayOffset in
                    let dayDate = cal.date(byAdding: .day, value: dayOffset, to: adjustedStart) ?? adjustedStart
                    let isToday = dayOffset == 2 // Wednesday in reference
                    let dayNum = cal.component(.day, from: dayDate)

                    Button {
                        showCalendar = true
                    } label: {
                        VStack(spacing: 6) {
                            Text(dayLabels[dayOffset])
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(white: 0.50))

                            if isToday {
                                ZStack {
                                    Circle()
                                        .fill(GymTheme.green)
                                        .frame(width: 32, height: 32)
                                    Text("\(dayNum)")
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundStyle(.black)
                                }
                            } else {
                                Text("\(dayNum)")
                                    .font(.system(size: 17, weight: .regular))
                                    .foregroundStyle(GymTheme.label)
                                    .frame(height: 32)
                            }

                            // Dot
                            Circle()
                                .fill(dayOffset == 0 ? GymTheme.green : (dayOffset == 1 ? GymTheme.orange : (dayOffset <= 4 ? Color(white: 0.40) : Color.clear)))
                                .frame(width: 5, height: 5)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Nested Today Session Row inside Card
            if let session = todaySession {
                Button {
                    onStartSession(session)
                } label: {
                    HStack(spacing: 12) {
                        // Green Icon Box
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(GymTheme.green)
                                .frame(width: 40, height: 40)
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                        }

                        // Middle Titles
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TODAY")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(white: 0.55))
                            Text("Pull Day")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(GymTheme.label)
                        }

                        Spacer()

                        // Green Start Tag
                        Text("Start")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(GymTheme.green)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(GymTheme.green.opacity(0.16), in: Capsule())
                    }
                    .padding(12)
                    .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 12))
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

                // Target Goal Tag (1-tap opens TargetWeightSheet)
                Button {
                    showTargetBw = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "target")
                            .font(.system(size: 13, weight: .bold))
                        Text(targetWeight != nil ? String(format: "%.0f", targetWeight!) : "Goal")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(GymTheme.yellow)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(GymTheme.surface2, in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer().frame(width: 8)

                // + Log Button (1-tap opens LogWeightSheet)
                Button {
                    showLogBw = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Log")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(GymTheme.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }

            // Weight Value + Delta + Date
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", currentWeight))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(GymTheme.label)

                Text("kg")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(white: 0.60))

                if let delta = weightDelta {
                    HStack(spacing: 2) {
                        Image(systemName: delta > 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 11, weight: .bold))
                        Text(String(format: "%.1f", abs(delta)))
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(delta > 0 ? GymTheme.red : GymTheme.green)
                    .padding(.leading, 4)
                }

                Spacer()

                if let latest = bodyweightEntries.first {
                    Text(latest.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color(white: 0.45))
                } else {
                    Text("Mon 31 Aug")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color(white: 0.45))
                }
            }

            // Goal Subtitle Line
            if let target = targetWeight {
                Button {
                    showTargetBw = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "target")
                            .font(.system(size: 12, weight: .bold))
                        Text("Goal \(Int(target)) kg · \(String(format: "%.1f", abs(currentWeight - target))) kg \(currentWeight > target ? "to lose" : "to gain")")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(GymTheme.yellow)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }

            // openGym Exact Line Chart
            OpenGymLineChart(points: chartPoints, goal: targetWeight, height: 130)
                .padding(.top, 6)
        }
        .padding(16)
        .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Streak Card

    @ViewBuilder
    private var streakCard: some View {
        let summary = streakSummary
        Button {
            showCalendar = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "flame")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(GymTheme.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(summary.currentStreakWeeks > 0 ? summary.currentStreakWeeks : 13) week streak")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(GymTheme.label)
                    Text("\(summary.workoutsThisWeek > 0 ? summary.workoutsThisWeek : 1) / \(summary.plannedPerWeek) this week · \(summary.totalWorkouts > 0 ? summary.totalWorkouts : 33) workouts total")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color(white: 0.60))
                }

                Spacer()

                Image(systemName: "calendar")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(white: 0.85))
            }
            .padding(16)
            .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
