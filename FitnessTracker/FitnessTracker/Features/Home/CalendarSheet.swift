import SwiftUI
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics
import RuleEngine

struct CalendarSheet: View {
    let plan: WeeklyPlan
    let catalog: CatalogStore
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \CompletedSessionModel.startedAt, order: .reverse)
    private var completedSessions: [CompletedSessionModel]

    @AppStorage("gym_accent_color") private var accentColorKey: String = "lime"
    private var activeAccent: Color { GymTheme.accent(for: accentColorKey) }

    @State private var selectedSessionForDetail: CompletedSessionModel?
    @State private var selectedDateForOverride: Date?

    private let dayHeaders = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

    /// Rolling window of months shown in the scroll: 15 back through 2 ahead,
    /// oldest first so scrolling down moves forward in time.
    private var months: [Date] {
        let cal = Calendar.appWeek
        let thisMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        return (-15...2).compactMap { cal.date(byAdding: .month, value: $0, to: thisMonth) }
    }

    private func monthKey(_ date: Date) -> String {
        let c = Calendar.appWeek.dateComponents([.year, .month], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)"
    }

    private var trainedSessionsByDay: [Date: [CompletedSessionModel]] {
        let cal = Calendar.appWeek
        return Dictionary(grouping: completedSessions.filter { $0.finishedAt != nil }) {
            cal.startOfDay(for: $0.startedAt)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                weekdayHeaderRow
                legendView

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 26, pinnedViews: [.sectionHeaders]) {
                            ForEach(months, id: \.self) { month in
                                Section {
                                    monthGrid(for: month)
                                } header: {
                                    monthHeader(for: month)
                                }
                                .id(monthKey(month))
                            }
                        }
                        .padding(.bottom, 24)
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            proxy.scrollTo(monthKey(Date()), anchor: .top)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .background(GymTheme.bgElevated.ignoresSafeArea())
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(activeAccent)
                }
            }
            .sheet(item: $selectedSessionForDetail) { session in
                WorkoutDetailSheet(session: session, catalog: catalog)
            }
            .sheet(isPresented: Binding(
                get: { selectedDateForOverride != nil },
                set: { if !$0 { selectedDateForOverride = nil } }
            )) {
                if let date = selectedDateForOverride {
                    DayOverrideSheet(date: date, plan: plan, onSaveOverride: { override in
                        var updated = WorkoutScheduleStore.userDayPlan
                        let key = Scheduling.isoDateKey(date, calendar: .appWeek)
                        if let override { updated[key] = override } else { updated.removeValue(forKey: key) }
                        WorkoutScheduleStore.saveDayPlan(updated)
                    }) { _ in
                        selectedDateForOverride = nil
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Fixed header rows

    private var weekdayHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(dayHeaders, id: \.self) { h in
                Text(h)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(white: 0.60))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func monthHeader(for month: Date) -> some View {
        let cal = Calendar.appWeek
        let monthSessions = completedSessions.filter {
            $0.finishedAt != nil && cal.isDate($0.startedAt, equalTo: month, toGranularity: .month)
        }
        let totalMs = monthSessions.reduce(0) { $0 + $1.actualDurationMin }
        let totalVol = monthSessions.reduce(0.0) { sum, s in
            sum + s.entries.reduce(0.0) { eSum, e in
                eSum + e.sets.reduce(0.0) { sSum, set in sSum + (set.actualLoadKg * Double(set.actualReps)) }
            }
        }

        VStack(alignment: .leading, spacing: 2) {
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.title3.weight(.bold))
                .foregroundStyle(GymTheme.label)

            if monthSessions.isEmpty {
                Text("No workouts")
                    .font(.caption.weight(.regular))
                    .foregroundStyle(Color(white: 0.60))
            } else {
                Text("\(monthSessions.count) workouts · \(totalMs / 60)h \(totalMs % 60)m · \(String(format: "%.1f kg", totalVol))")
                    .font(.caption.weight(.regular))
                    .foregroundStyle(Color(white: 0.60))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .background(GymTheme.bgElevated)
    }

    // MARK: - Month grid

    @ViewBuilder
    private func monthGrid(for month: Date) -> some View {
        let cal = Calendar.appWeek
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: month)) ?? month
        let numDays = (cal.range(of: .day, in: .month, for: startOfMonth) ?? 1..<31).count
        let firstWeekday = cal.component(.weekday, from: startOfMonth)
        let startOffset = (firstWeekday + 5) % 7
        let daysByDate = trainedSessionsByDay
        let rows = (startOffset + numDays + 6) / 7

        VStack(spacing: 5) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(0..<7, id: \.self) { col in
                        let dayNum = row * 7 + col - startOffset + 1
                        if dayNum >= 1 && dayNum <= numDays {
                            let dayDate = cal.date(byAdding: .day, value: dayNum - 1, to: startOfMonth) ?? startOfMonth
                            dayTile(dayNum: dayNum, dayDate: dayDate,
                                    trainedSessions: daysByDate[cal.startOfDay(for: dayDate)] ?? [])
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayTile(dayNum: Int, dayDate: Date, trainedSessions: [CompletedSessionModel]) -> some View {
        let cal = Calendar.appWeek
        let isToday = cal.isDateInToday(dayDate)
        let isTrained = !trainedSessions.isEmpty
        let isPlanned = WorkoutScheduleStore.effectiveRoutineID(for: dayDate) != nil
        let isRescheduled = WorkoutScheduleStore.isRescheduled(for: dayDate)

        Button {
            if let first = trainedSessions.first {
                selectedSessionForDetail = first
            } else {
                selectedDateForOverride = dayDate
            }
        } label: {
            VStack(spacing: 2) {
                Text("\(dayNum)")
                    .font(.system(size: 15, weight: isTrained ? .bold : .regular))
                    .foregroundStyle(isTrained ? activeAccent : GymTheme.label)

                Circle()
                    .fill(isTrained ? activeAccent : (isRescheduled ? GymTheme.orange : (isPlanned ? Color(white: 0.60) : Color.clear)))
                    .frame(width: 4.5, height: 4.5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                isTrained ? activeAccent.opacity(0.18) : GymTheme.surface,
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                isToday ? RoundedRectangle(cornerRadius: 10).stroke(activeAccent, lineWidth: 1.8) : nil
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Legend

    private var legendView: some View {
        HStack(spacing: 16) {
            HStack(spacing: 5) {
                Circle().fill(activeAccent).frame(width: 5, height: 5)
                Text("Trained")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color(white: 0.65))
            }
            HStack(spacing: 5) {
                Circle().fill(Color(white: 0.60)).frame(width: 5, height: 5)
                Text("Planned")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color(white: 0.65))
            }
            HStack(spacing: 5) {
                Circle().fill(GymTheme.orange).frame(width: 5, height: 5)
                Text("Rescheduled")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color(white: 0.65))
            }
        }
    }
}
