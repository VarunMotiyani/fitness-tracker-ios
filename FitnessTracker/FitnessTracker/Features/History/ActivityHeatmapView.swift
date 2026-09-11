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

    // Precomputed once per instance. Previously these were computed properties
    // hit once per grid cell (52×7 = 364 cells) on every body pass — each call
    // rebuilding a dictionary and running String(format:) — which dominated the
    // Stats tab's CPU time.
    private let weeks: [[Date]]
    /// Intensity (0…1) per grid cell, parallel to `weeks`. Precomputed so the
    /// 364-cell body doesn't run `String(format:)` + a dictionary lookup per
    /// cell on every render.
    private let cellIntensities: [[Double]]
    private let totalWorkoutsThisYear: Int

    public init(
        activityDays: [Date: (count: Int, volume: Double)] = [:],
        calendar: Calendar = .appWeek,
        now: Date = .now,
        accentColor: Color = GymTheme.green
    ) {
        self.accentColor = accentColor

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
    }

    private static func key(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workout Activity")
                        .font(.headline)
                    Text("\(totalWorkoutsThisYear) sessions in past 52 weeks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            
            // 52-week horizontal scrollable grid
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(cellIntensities.indices, id: \.self) { wi in
                        VStack(spacing: 3) {
                            ForEach(cellIntensities[wi].indices, id: \.self) { di in
                                RoundedRectangle(cornerRadius: 2.5)
                                    .fill(shade(for: cellIntensities[wi][di]))
                                    .frame(width: 11, height: 11)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
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
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding()
        .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 14))
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
