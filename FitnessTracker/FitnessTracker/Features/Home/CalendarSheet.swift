import SwiftUI
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics

struct CalendarSheet: View {
    let plan: WeeklyPlan
    let catalog: CatalogStore
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \CompletedSessionModel.startedAt, order: .reverse)
    private var completedSessions: [CompletedSessionModel]

    @AppStorage("gym_accent_color") private var accentColorKey: String = "lime"
    private var activeAccent: Color { GymTheme.accent(for: accentColorKey) }

    @State private var currentMonth: Date = Date()
    @State private var selectedSessionForDetail: CompletedSessionModel?
    @State private var selectedDateForOverride: Date?

    private let dayHeaders = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

    private var calculatedHeight: CGFloat {
        let cal = Calendar.isoUTC
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: currentMonth)) ?? currentMonth
        let range = cal.range(of: .day, in: .month, for: startOfMonth) ?? 1..<31
        let firstWeekday = cal.component(.weekday, from: startOfMonth)
        let startOffset = (firstWeekday + 5) % 7
        let rows = (startOffset + range.count + 6) / 7
        return rows > 5 ? 495 : 445
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // Header (Month + Year + Subtitle Stats)
                headerView

                // Calendar Grid
                calendarGridView

                // Legend
                legendView

                Text("Tap a trained day for details · tap any other day to plan a session")
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(Color(white: 0.45))
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 16)
            .background(GymTheme.bgElevated.ignoresSafeArea())
            .sheet(item: $selectedSessionForDetail) { session in
                WorkoutDetailSheet(session: session, catalog: catalog)
            }
            .sheet(isPresented: Binding(
                get: { selectedDateForOverride != nil },
                set: { if !$0 { selectedDateForOverride = nil } }
            )) {
                if let date = selectedDateForOverride {
                    DayOverrideSheet(date: date, plan: plan) { _ in
                        selectedDateForOverride = nil
                    }
                }
            }
        }
        .presentationDetents([.height(calculatedHeight)])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    @ViewBuilder
    private var headerView: some View {
        let cal = Calendar.isoUTC
        let monthName = currentMonth.formatted(.dateTime.month(.wide).year())
        let monthSessions = completedSessions.filter {
            $0.finishedAt != nil && cal.isDate($0.startedAt, equalTo: currentMonth, toGranularity: .month)
        }
        let totalMs = monthSessions.reduce(0) { $0 + $1.actualDurationMin }
        let totalVol = monthSessions.reduce(0.0) { sum, s in
            sum + s.entries.reduce(0.0) { eSum, e in
                eSum + e.sets.reduce(0.0) { sSum, set in sSum + (set.actualLoadKg * Double(set.actualReps)) }
            }
        }

        VStack(spacing: 3) {
            HStack {
                Button {
                    currentMonth = cal.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(GymTheme.label)
                        .frame(width: 36, height: 36)
                        .background(GymTheme.surface2, in: Circle())
                }

                Spacer()

                Text(monthName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(GymTheme.label)

                Spacer()

                Button {
                    currentMonth = cal.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(GymTheme.label)
                        .frame(width: 36, height: 36)
                        .background(GymTheme.surface2, in: Circle())
                }
            }

            if monthSessions.isEmpty {
                Text("No workouts this month")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(white: 0.55))
            } else {
                Text("\(monthSessions.count) workouts · \(totalMs / 60)h \(totalMs % 60)m · \(String(format: "%.1f kg", totalVol))")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(white: 0.55))
            }
        }
    }

    // MARK: - Calendar Grid

    @ViewBuilder
    private var calendarGridView: some View {
        let cal = Calendar.isoUTC
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: currentMonth)) ?? currentMonth
        let range = cal.range(of: .day, in: .month, for: startOfMonth) ?? 1..<31
        let numDays = range.count

        // Determine first weekday offset (Monday = 0)
        let firstWeekday = cal.component(.weekday, from: startOfMonth)
        let startOffset = (firstWeekday + 5) % 7

        let daysByDate = Dictionary(grouping: completedSessions.filter { $0.finishedAt != nil }) {
            cal.startOfDay(for: $0.startedAt)
        }

        VStack(spacing: 6) {
            // Day headers
            HStack(spacing: 0) {
                ForEach(dayHeaders, id: \.self) { h in
                    Text(h)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(white: 0.45))
                        .frame(maxWidth: .infinity)
                }
            }

            // Grid tiles
            let totalCells = startOffset + numDays
            let rows = (totalCells + 6) / 7

            VStack(spacing: 5) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 5) {
                        ForEach(0..<7, id: \.self) { col in
                            let cellIndex = row * 7 + col
                            let dayNum = cellIndex - startOffset + 1

                            if dayNum >= 1 && dayNum <= numDays {
                                let dayDate = cal.date(byAdding: .day, value: dayNum - 1, to: startOfMonth) ?? startOfMonth
                                let dayStart = cal.startOfDay(for: dayDate)
                                let isToday = cal.isDateInToday(dayDate)
                                let trainedSessions = daysByDate[dayStart] ?? []
                                let isTrained = !trainedSessions.isEmpty
                                let isPlanned = col == 0 || col == 2 || col == 4

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
                                            .fill(isTrained ? activeAccent : (isPlanned ? Color(white: 0.40) : Color.clear))
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
    }

    // MARK: - Legend

    @ViewBuilder
    private var legendView: some View {
        HStack(spacing: 16) {
            HStack(spacing: 5) {
                Circle().fill(activeAccent).frame(width: 5, height: 5)
                Text("Trained")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(white: 0.65))
            }
            HStack(spacing: 5) {
                Circle().fill(Color(white: 0.40)).frame(width: 5, height: 5)
                Text("Planned")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(white: 0.65))
            }
            HStack(spacing: 5) {
                Circle().fill(GymTheme.orange).frame(width: 5, height: 5)
                Text("Rescheduled")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(white: 0.65))
            }
        }
        .padding(.top, 4)
    }
}
