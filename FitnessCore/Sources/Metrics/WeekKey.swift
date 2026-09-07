import Foundation

public enum WeekStart: String, Sendable, Codable, CaseIterable {
    case monday, sunday
}

public enum WeekKey {
    /// The start-of-week date for `date` given `weekStart`.
    public static func startOfWeek(_ date: Date, weekStart: WeekStart = .monday, calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.firstWeekday = (weekStart == .sunday) ? 1 : 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? date
    }

    /// A stable "YYYY-Wnn" key for grouping/streaks.
    public static func key(_ date: Date, weekStart: WeekStart = .monday, calendar: Calendar = .current) -> String {
        var cal = calendar
        cal.firstWeekday = (weekStart == .sunday) ? 1 : 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let y = comps.yearForWeekOfYear ?? 0
        let w = comps.weekOfYear ?? 0
        return String(format: "%04d-W%02d", y, w)
    }
}
