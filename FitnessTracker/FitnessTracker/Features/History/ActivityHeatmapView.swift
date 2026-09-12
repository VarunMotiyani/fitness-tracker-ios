import SwiftUI
import FitnessDomain
import Metrics

public struct ActivityDay: Identifiable, Sendable {
    public let id: String
    public let date: Date
    public let sessionCount: Int
    public let volumeKg: Double
    
    public init(date: Date, sessionCount: Int = 0, volumeKg: Double = 0) {
        self.date = date
        self.sessionCount = sessionCount
        self.volumeKg = volumeKg
        let formatter = ISO8601DateFormatter()
        self.id = formatter.string(from: date)
    }
}

public struct ActivityHeatmapView: View {
    public var accentColor: Color
    public var onDay: ((Date) -> Void)?

    // Precomputed once per instance. Previously these were computed properties
    // hit once per grid cell (52×7 = 364 cells) on every body pass — each call
    // rebuilding a dictionary and running String(format:) — which dominated the
    // Stats tab's CPU time.
    private let calendar: Calendar
    private let now: Date
    private let weeks: [[Date]]
    /// Intensity (0…1) per grid cell, parallel to `weeks`. Precomputed so the
    /// 364-cell body doesn't run `String(format:)` + a dictionary lookup per
    /// cell on every render.
    private let cellIntensities: [[Double]]
    private let totalWorkoutsThisYear: Int
    private let monthLabels: [Int: String]

    public init(
        activityDays: [Date: (count: Int, volume: Double)] = [:],
        calendar: Calendar = .appWeek,
        now: Date = .now,
        accentColor: Color = GymTheme.green,
        onDay: ((Date) -> Void)? = nil
    ) {
        self.accentColor = accentColor
        self.onDay = onDay
        self.calendar = calendar
        self.now = now

        var weekGrid: [[Date]] = []
        let currentWeekStart = WeekKey.startOfWeek(now, weekStart: .monday, calendar: calendar)
        if let start = calendar.date(byAdding: .weekOfYear, value: -51, to: currentWeekStart) {
            for w in 0..<52 {
                guard let weekDate = calendar.date(byAdding: .weekOfYear, value: w, to: start) else { continue }
                var days: [Date] = []
                for d in 0..<7 {
                    if let day = calendar.date(byAdding: .day, value: d, to: weekDate) { days.append(day) }
                }
                weekGrid.append(days)
            }
        }
        self.weeks = weekGrid

        var index: [String: (count: Int, volume: Double)] = [:]
        for (date, v) in activityDays {
            let k = Self.key(date, calendar)
            let prev = index[k] ?? (0, 0)
            index[k] = (prev.count + v.count, prev.volume + v.volume)
        }
        self.totalWorkoutsThisYear = activityDays.values.reduce(0) { $0 + $1.count }
        let maxVol = max(1.0, index.values.map(\.volume).max() ?? 1.0)

        self.cellIntensities = weekGrid.map { week in
            week.map { day -> Double in
                guard let info = index[Self.key(day, calendar)], info.count > 0 else { return 0 }
                if info.count >= 2 { return 1 }
                let volFrac = min(1, info.volume / maxVol)
                return max(0.35, 0.35 + volFrac * 0.65)
            }
        }

        var labels: [Int: String] = [:]
        var lastMonth: Int? = nil
        let shortMonths = calendar.shortStandaloneMonthSymbols
        for wi in 0..<weekGrid.count {
            guard let firstDay = weekGrid[wi].first else { continue }
            let m = calendar.component(.month, from: firstDay)
            if m != lastMonth {
                labels[wi] = shortMonths[m - 1]
                lastMonth = m
            }
        }
        self.monthLabels = labels
    }

    private static func key(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(totalWorkoutsThisYear) sessions in past 52 weeks")
                    .font(.footnote)
                    .foregroundStyle(Color(white: 0.60))
                Spacer()
            }
            
            // 52-week horizontal scrollable grid anchored to latest week
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        // Month timeline labels
                        HStack(spacing: 3) {
                            ForEach(weeks.indices, id: \.self) { wi in
                                ZStack(alignment: .leading) {
                                    if let label = monthLabels[wi] {
                                        Text(label)
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(Color(white: 0.60))
                                            .fixedSize()
                                    }
                                }
                                .frame(width: 11, height: 12, alignment: .leading)
                            }
                        }

                        // 7x52 Grid
                        HStack(spacing: 3) {
                            ForEach(cellIntensities.indices, id: \.self) { wi in
                                VStack(spacing: 3) {
                                    ForEach(cellIntensities[wi].indices, id: \.self) { di in
                                        dayCell(weekIndex: wi, dayIndex: di)
                                    }
                                }
                                .id(wi)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .defaultScrollAnchor(.trailing)
                .onAppear {
                    if let lastIndex = cellIntensities.indices.last {
                        DispatchQueue.main.async {
                            proxy.scrollTo(lastIndex, anchor: .trailing)
                        }
                    }
                }
            }
            
            // Legend (5-level intensity gradient)
            HStack(spacing: 6) {
                Text("Less time")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach([0.0, 0.25, 0.50, 0.75, 1.0], id: \.self) { level in
                    shade(for: level)
                        .frame(width: 10, height: 10)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
                Text("More time")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func dayCell(weekIndex wi: Int, dayIndex di: Int) -> some View {
        let day = weeks[wi][di]
        let intensity = cellIntensities[wi][di]
        let isToday = calendar.isDateInToday(day)
        let isFuture = day > now && !isToday

        Button {
            guard !isFuture else { return }
            #if canImport(UIKit)
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            #endif
            onDay?(day)
        } label: {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(isFuture ? GymTheme.surface3.opacity(0.3) : shade(for: intensity))
                .frame(width: 11, height: 11)
                .overlay(
                    isToday ? RoundedRectangle(cornerRadius: 2.5).stroke(Color.white, lineWidth: 1.5) : nil
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .contextMenu {
            if !isFuture {
                Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.headline)
                if intensity > 0 {
                    Label("Trained Day", systemImage: "dumbbell.fill")
                } else {
                    Label("Rest Day", systemImage: "moon.stars.fill")
                }
                Divider()
                Button {
                    onDay?(day)
                } label: {
                    Label("View Day Activity", systemImage: "calendar.badge.clock")
                }
            }
        }
    }

    private func shade(for level: Double) -> Color {
        // Decorative grid cell, not text — the a11y contrast sweep raised this
        // to the same 0.60 gray as the card background above, so every
        // no-activity cell (level 0, the majority of a 52-week grid) vanished
        // into the card and only the green "had a workout" cells stayed visible.
        guard level > 0 else { return GymTheme.surface3 }
        // 0.35 → faint, 1.0 → full accent.
        return accentColor.opacity(0.30 + level * 0.70)
    }
}
