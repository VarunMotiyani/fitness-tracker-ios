import SwiftUI
import SwiftData
import FitnessDomain
import Metrics

/// Renders the most recent generated weekly recap (`WeeklySummaryModel`, one row
/// per ISO week, written by `ProactiveCoordinator.generateWeeklySummary`). The
/// recap's own prose (`headline` / `summaryBody` / `nextWeekFocus`) sits up top;
/// a few deterministic rows computed inline from logged data sit below it so the
/// screen still says something concrete even if the prose is thin.
struct WeeklySummaryView: View {
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \WeeklySummaryModel.weekStartDate, order: .reverse)
    private var summaries: [WeeklySummaryModel]

    @Query(sort: \CompletedSessionModel.startedAt, order: .reverse)
    private var completedSessions: [CompletedSessionModel]

    @Query(sort: \PersonalRecordModel.date, order: .reverse)
    private var prRecords: [PersonalRecordModel]

    @AppStorage("gym_accent_color") private var accentColorKey: String = "lime"
    private var activeAccent: Color { GymTheme.accent(for: accentColorKey) }

    // MARK: - Displayed summary

    /// The recap to show: the most recent one whose week has actually ended.
    /// After an upgrade a pre-existing `WeeklySummaryModel` may be stamped on the
    /// *current* ISO week; that row would otherwise render under the "Last week"
    /// header for a week, so skip anything not strictly before this week's start.
    private var displayed: WeeklySummaryModel? {
        guard let currentWeekStart = Calendar.isoUTC.dateInterval(of: .weekOfYear, for: .now)?.start
        else { return summaries.first }
        return summaries.first { $0.weekStartDate < currentWeekStart }
    }

    // MARK: - Deterministic rows (computed inline from logged data)

    /// The week the recap actually describes: the displayed summary's own
    /// `weekStartDate` (the prior ISO week, per `generateWeeklySummary`). Falls
    /// back to the current ISO week Monday only when there is no summary (the
    /// empty-state branch renders `emptyState` anyway, so it's moot).
    private var weekStart: Date {
        if let stamped = displayed?.weekStartDate { return stamped }
        let cal = Calendar.isoUTC
        return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
    }

    /// `[weekStart, weekEnd)` — the deterministic rows describe the same single
    /// week as the prose, not an open-ended "since Monday".
    private var weekEnd: Date {
        Calendar.isoUTC.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart
    }

    private var finishedSessions: [CompletedSessionModel] {
        completedSessions.filter { $0.finishedAt != nil }
    }

    private var sessionsThisWeek: Int {
        finishedSessions.filter { $0.startedAt >= weekStart && $0.startedAt < weekEnd }.count
    }

    private var prsThisWeek: Int {
        prRecords.filter { $0.date >= weekStart && $0.date < weekEnd }.count
    }

    private var currentStreakWeeks: Int {
        // `plannedPerWeek` only feeds adherence fields, not `currentStreakWeeks`.
        // Evaluate the streak as of the end of the displayed week so all three
        // stat rows describe the same week, not "as of today".
        StreakCalculator.computeSummary(
            from: finishedSessions.map { $0.toSnapshot() },
            plannedPerWeek: 3,
            now: displayed.map { Calendar.isoUTC.date(byAdding: .day, value: 6, to: $0.weekStartDate) ?? .now } ?? .now
        ).currentStreakWeeks
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let latest = displayed {
                        headerView(for: latest)
                        recapCard(for: latest)
                        deterministicRowsCard
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(GymTheme.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(activeAccent)
                }
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func headerView(for summary: WeeklySummaryModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last week")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(GymTheme.label)
            Text("Week of \(summary.weekStartDate.formatted(.dateTime.weekday(.wide).day().month(.wide)))")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(white: 0.60))
        }
        .padding(.top, 12)
        .padding(.bottom, 2)
    }

    // MARK: - Recap Card (generated prose)

    @ViewBuilder
    private func recapCard(for summary: WeeklySummaryModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(summary.headline)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(GymTheme.label)
                .fixedSize(horizontal: false, vertical: true)

            if !summary.summaryBody.isEmpty {
                Text(summary.summaryBody)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color(white: 0.70))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !summary.nextWeekFocus.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEXT WEEK")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(white: 0.50))
                    Text(summary.nextWeekFocus)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(activeAccent)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Deterministic Rows Card

    @ViewBuilder
    private var deterministicRowsCard: some View {
        VStack(spacing: 0) {
            summaryRow(
                icon: "dumbbell.fill",
                iconColor: GymTheme.green,
                title: "Sessions completed",
                value: "\(sessionsThisWeek)"
            )
            Divider().background(Color.white.opacity(0.08))
            summaryRow(
                icon: "flame.fill",
                iconColor: GymTheme.orange,
                title: "Current streak",
                value: currentStreakWeeks == 1 ? "1 week" : "\(currentStreakWeeks) weeks"
            )
            Divider().background(Color.white.opacity(0.08))
            summaryRow(
                icon: "trophy.fill",
                iconColor: GymTheme.yellow,
                title: "Personal records",
                value: "\(prsThisWeek)"
            )
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 14)
        .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func summaryRow(icon: String, iconColor: Color, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(iconColor)
                .frame(width: 28)
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(GymTheme.label)
            Spacer()
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(GymTheme.label)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Color(white: 0.45))
            Text("No weekly recap yet")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(GymTheme.label)
            Text("Check back after your week wraps up.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(white: 0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}
