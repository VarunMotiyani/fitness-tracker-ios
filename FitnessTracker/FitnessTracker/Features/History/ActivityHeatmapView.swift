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
    
    private var totalWorkoutsThisYear: Int {
        activityDays.values.reduce(0) { $0 + $1.count }
    }

    private var maxVolume: Double {
        let maxVal = activityDays.values.map(\.volume).max() ?? 0.0
        return max(1000.0, maxVal)
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
            
            // Legend
            HStack(spacing: 6) {
                Text("Less")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                cellColor(count: 0)
                    .frame(width: 10, height: 10)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                cellColor(count: 1, volume: maxVolume * 0.2)
                    .frame(width: 10, height: 10)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                cellColor(count: 1, volume: maxVolume * 0.5)
                    .frame(width: 10, height: 10)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                cellColor(count: 1, volume: maxVolume * 0.9)
                    .frame(width: 10, height: 10)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                Text("More")
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
        let (count, vol) = dayInfo(for: day)
        
        RoundedRectangle(cornerRadius: 2.5)
            .fill(cellColor(count: count, volume: vol))
            .frame(width: 11, height: 11)
    }

    private func dayInfo(for day: Date) -> (count: Int, volume: Double) {
        let targetStart = calendar.startOfDay(for: day)
        for (k, v) in activityDays {
            if calendar.isDate(k, inSameDayAs: targetStart) {
                return (v.count, v.volume)
            }
        }
        return (0, 0)
    }
    
    private func cellColor(count: Int, volume: Double = 0) -> Color {
        guard count > 0 else {
            return Color(white: 0.22)
        }
        if volume >= maxVolume * 0.66 || count >= 2 {
            return accentColor
        } else if volume >= maxVolume * 0.33 {
            return accentColor.opacity(0.70)
        } else {
            return accentColor.opacity(0.40)
        }
    }
}
