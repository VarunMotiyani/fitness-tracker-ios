import SwiftUI
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics
import RuleEngine

struct DayActivityItem: Identifiable {
    let date: Date
    var id: TimeInterval { date.timeIntervalSince1970 }

    init(date: Date) {
        self.date = date
    }
}

struct DayActivitySheet: View {
    let date: Date
    let plan: WeeklyPlan
    let catalog: CatalogStore
    var onSelectSession: ((CompletedSessionModel) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @Query(sort: \CompletedSessionModel.startedAt, order: .reverse)
    private var completedSessions: [CompletedSessionModel]

    @Query(sort: \DailyCheckinModel.date, order: .reverse)
    private var dailyCheckins: [DailyCheckinModel]

    @Query(sort: \BodyweightEntryModel.date, order: .reverse)
    private var bodyweightEntries: [BodyweightEntryModel]

    @Query(sort: \PersonalRecordModel.date, order: .reverse)
    private var prRecords: [PersonalRecordModel]

    @AppStorage("gym_accent_color") private var accentColorKey: String = "lime"
    private var activeAccent: Color { GymTheme.accent(for: accentColorKey) }

    @State private var detailedSession: CompletedSessionModel? = nil

    init(
        date: Date,
        plan: WeeklyPlan,
        catalog: CatalogStore,
        onSelectSession: ((CompletedSessionModel) -> Void)? = nil
    ) {
        self.date = date
        self.plan = plan
        self.catalog = catalog
        self.onSelectSession = onSelectSession
    }

    private var daySessions: [CompletedSessionModel] {
        let cal = Calendar.appWeek
        return completedSessions.filter {
            $0.finishedAt != nil && cal.isDate($0.startedAt, inSameDayAs: date)
        }
    }

    private var dayCheckin: DailyCheckinModel? {
        dailyCheckins.first { Calendar.appWeek.isDate($0.date, inSameDayAs: date) }
    }

    private var dayWeight: BodyweightEntryModel? {
        bodyweightEntries.first { Calendar.appWeek.isDate($0.date, inSameDayAs: date) }
    }

    private var dayPRs: [PersonalRecordModel] {
        prRecords.filter { Calendar.appWeek.isDate($0.date, inSameDayAs: date) }
    }

    private var isToday: Bool {
        Calendar.appWeek.isDateInToday(date)
    }

    private var scheduleStatusText: String {
        if let routineID = WorkoutScheduleStore.effectiveRoutineID(for: date) {
            let routineName: String
            if let planned = plan.sessions.first(where: { $0.id == routineID }) {
                routineName = RoutineNaming.dayName(for: planned.focusMuscles)
            } else {
                routineName = "Workout"
            }
            let rescheduled = WorkoutScheduleStore.isRescheduled(for: date)
            return rescheduled ? "Rescheduled: \(routineName)" : "Scheduled: \(routineName)"
        } else {
            return "Scheduled Rest Day"
        }
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard

                    if !daySessions.isEmpty {
                        workoutsSection
                    } else {
                        restDayCard
                    }

                    if let checkin = dayCheckin {
                        checkinCard(checkin)
                    }

                    if let weight = dayWeight {
                        bodyweightCard(weight)
                    }
                }
                .padding(20)
            }
            .background(GymTheme.bgElevated.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color(white: 0.5))
                    }
                }
            }
            .sheet(item: $detailedSession) { session in
                WorkoutDetailSheet(session: session, catalog: catalog)
            }
        }
        .presentationDetents([.fraction(0.45), .medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Subviews

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(GymTheme.label)
                Spacer()
                if isToday {
                    Text("Today")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(activeAccent.opacity(0.18), in: Capsule())
                        .foregroundStyle(activeAccent)
                }
            }

            Text(scheduleStatusText)
                .font(.footnote)
                .foregroundStyle(Color(white: 0.60))
        }
    }

    private var restDayCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(GymTheme.surface2)
                    .frame(width: 48, height: 48)
                Image(systemName: "moon.stars.fill")
                    .font(.title3)
                    .foregroundStyle(GymTheme.violet)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Rest Day")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(GymTheme.label)
                Text("No workouts logged on this day.")
                    .font(.footnote)
                    .foregroundStyle(Color(white: 0.60))
            }
            Spacer()
        }
        .padding(14)
        .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private func routineTitle(for session: CompletedSessionModel) -> String {
        if let plannedID = session.plannedSessionID,
           let planned = plan.sessions.first(where: { $0.id == plannedID }) {
            return RoutineNaming.dayName(for: planned.focusMuscles)
        }
        let muscles = session.entries.compactMap { entry -> [MuscleGroup]? in
            guard let ex = catalog.exercise(id: entry.exerciseID) else { return nil }
            return [ex.primaryMuscle] + ex.secondaryMuscles
        }.flatMap { $0 }
        let name = RoutineNaming.dayName(for: muscles)
        return name.isEmpty ? "Workout" : name
    }

    private func totalSets(for session: CompletedSessionModel) -> Int {
        session.entries.flatMap(\.sets).filter { !$0.isWarmup }.count
    }

    private func totalTonnage(for session: CompletedSessionModel) -> Double {
        session.entries.flatMap(\.sets).reduce(0.0) { $0 + ($1.actualLoadKg * Double($1.actualReps)) }
    }

    private var workoutsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Workouts")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(white: 0.60))
                .textCase(.uppercase)

            ForEach(daySessions, id: \.id) { session in
                let title = routineTitle(for: session)
                let setsCount = totalSets(for: session)
                let tonnage = totalTonnage(for: session)
                let tonnageStr = NumberFormatter.localizedString(from: NSNumber(value: Int(tonnage)), number: .decimal)
                let prCount = dayPRs.filter { $0.sessionID == session.id }.count

                Button {
                    if let onSelectSession {
                        onSelectSession(session)
                    } else {
                        detailedSession = session
                    }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(activeAccent.opacity(0.18))
                                .frame(width: 44, height: 44)
                            Image(systemName: "dumbbell.fill")
                                .font(.body.weight(.bold))
                                .foregroundStyle(activeAccent)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(GymTheme.label)

                            Text("\(session.actualDurationMin)m · \(setsCount) sets · \(tonnageStr) kg\(prCount > 0 ? " · \(prCount) PRs" : "")")
                                .font(.footnote)
                                .foregroundStyle(Color(white: 0.65))
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color(white: 0.40))
                    }
                    .padding(14)
                    .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func checkinCard(_ checkin: DailyCheckinModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "heart.text.square.fill")
                    .foregroundStyle(GymTheme.violet)
                Text("Daily Check-in")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(white: 0.60))
                    .textCase(.uppercase)
            }

            HStack(spacing: 12) {
                if let sleep = checkin.sleepQuality {
                    metricBadge(label: "Sleep", value: "\(sleep)/10", icon: "bed.double.fill", color: GymTheme.blue)
                }
                if let soreness = checkin.soreness {
                    metricBadge(label: "Soreness", value: "\(soreness)/10", icon: "figure.walk", color: GymTheme.orange)
                }
            }

            if let note = checkin.note, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(GymTheme.label)
                    .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private func metricBadge(label: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text("\(label): \(value)")
                .font(.footnote.weight(.medium))
                .foregroundStyle(GymTheme.label)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 8))
    }

    private func bodyweightCard(_ weight: BodyweightEntryModel) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(GymTheme.yellow.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: "scalemass.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(GymTheme.yellow)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Bodyweight")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color(white: 0.60))
                Text(String(format: "%.1f kg", weight.kg))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(GymTheme.label)
            }
            Spacer()
        }
        .padding(14)
        .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}
