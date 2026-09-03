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
    public let activityDays: [Date: (count: Int, volume: Double)]
    public let calendar: Calendar
    public let now: Date
    public var accentColor: Color
    
    public init(
        activityDays: [Date: (count: Int, volume: Double)] = [:],
        calendar: Calendar = .isoUTC,
        now: Date = .now,
        accentColor: Color = GymTheme.green
    ) {
        self.activityDays = activityDays
        self.calendar = calendar
        self.now = now
        self.accentColor = accentColor
    }
    
    private var weeks: [[Date]] {
        var result: [[Date]] = []
        let currentWeekStart = WeekKey.startOfWeek(now, weekStart: .monday, calendar: calendar)
        guard let start = calendar.date(byAdding: .weekOfYear, value: -51, to: currentWeekStart) else {
            return []
        }
        for w in 0..<52 {
            guard let weekDate = calendar.date(byAdding: .weekOfYear, value: w, to: start) else { continue }
            var days: [Date] = []
            for d in 0..<7 {
                if let day = calendar.date(byAdding: .day, value: d, to: weekDate) {
                    days.append(day)
                }
            }
            result.append(days)
        }
        return result
    }
    
    /// Day → activity, keyed by a stable `yyyy-MM-dd` string so a cell lookup is O(1) and
    /// never depends on `Date` equality across calendars or times of day (the reason the
    /// grid was rendering blank).
    private var dayIndex: [String: (count: Int, volume: Double)] {
        var out: [String: (count: Int, volume: Double)] = [:]
        for (date, v) in activityDays {
            let k = Self.key(date, calendar)
            let prev = out[k] ?? (0, 0)
            out[k] = (prev.count + v.count, prev.volume + v.volume)
        }
        return out
    }

    private static func key(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private var totalWorkoutsThisYear: Int {
        activityDays.values.reduce(0) { $0 + $1.count }
    }

    private var maxDayVolume: Double {
        max(1.0, dayIndex.values.map(\.volume).max() ?? 1.0)
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
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: 3) {
                            ForEach(week, id: \.self) { day in
                                dayCell(for: day)
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
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 14))
    }
    
    @ViewBuilder
    private func dayCell(for day: Date) -> some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(shade(for: intensity(for: day)))
            .frame(width: 11, height: 11)
    }

    /// 0 = no session that day; otherwise a 0…1 level. A session day is always at least
    /// 0.35 so it reads as trained; volume relative to the busiest day nudges it up.
    private func intensity(for day: Date) -> Double {
        guard let info = dayIndex[Self.key(day, calendar)], info.count > 0 else { return 0 }
        if info.count >= 2 { return 1 }
        let volFrac = min(1, info.volume / maxDayVolume)
        return max(0.35, 0.35 + volFrac * 0.65)
    }

    private func shade(for level: Double) -> Color {
        guard level > 0 else { return Color(white: 0.22) }
        // 0.35 → faint, 1.0 → full accent.
        return accentColor.opacity(0.30 + level * 0.70)
    }
}
