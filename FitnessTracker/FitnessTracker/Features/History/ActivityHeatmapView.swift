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
    
    public init(
        activityDays: [Date: (count: Int, volume: Double)] = [:],
        calendar: Calendar = .isoUTC,
        now: Date = .now
    ) {
        self.activityDays = activityDays
        self.calendar = calendar
        self.now = now
    }
    
    private var weeks: [[Date]] {
        // Build 52 weeks leading up to today
        var result: [[Date]] = []
        let today = calendar.startOfDay(for: now)
        guard let oneYearAgo = calendar.date(byAdding: .weekOfYear, value: -51, to: today) else {
            return []
        }
        
        var current = oneYearAgo
        var currentWeek: [Date] = []
        
        while current <= today {
            currentWeek.append(current)
            if currentWeek.count == 7 {
                result.append(currentWeek)
                currentWeek = []
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        if !currentWeek.isEmpty {
            result.append(currentWeek)
        }
        return result
    }
    
    private var totalWorkoutsThisYear: Int {
        activityDays.values.reduce(0) { $0 + $1.count }
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
                cellColor(count: 1, volume: 1000)
                    .frame(width: 10, height: 10)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                cellColor(count: 1, volume: 5000)
                    .frame(width: 10, height: 10)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                cellColor(count: 1, volume: 10000)
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
        let startOfDay = calendar.startOfDay(for: day)
        let info = activityDays[startOfDay]
        let count = info?.count ?? 0
        let vol = info?.volume ?? 0
        
        RoundedRectangle(cornerRadius: 2.5)
            .fill(cellColor(count: count, volume: vol))
            .frame(width: 11, height: 11)
    }
    
    private func cellColor(count: Int, volume: Double = 0) -> Color {
        guard count > 0 else {
            return Color(white: 0.22)
        }
        if volume > 8000 || count > 1 {
            return Color.green
        } else if volume > 4000 {
            return Color.green.opacity(0.75)
        } else {
            return Color.green.opacity(0.45)
        }
    }
}
