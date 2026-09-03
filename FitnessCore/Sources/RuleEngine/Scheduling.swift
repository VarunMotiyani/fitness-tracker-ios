import Foundation
import FitnessDomain

public enum Scheduling {
    public static func isoDateKey(_ date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        let d = comps.day ?? 0
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// The routine that applies on `date`: a `dayPlan[iso]` override ("rest" -> nil, or a
    /// routine id) wins; otherwise the weekday's assigned routine from `week`.
    public static func effectiveRoutineID(
        week: [Int: String],
        dayPlan: [String: String],
        date: Date,
        calendar: Calendar = .current
    ) -> String? {
        let iso = isoDateKey(date, calendar: calendar)
        if let override = dayPlan[iso] {
            if override.lowercased() == "rest" {
                return nil
            }
            return override
        }
        let weekday = calendar.component(.weekday, from: date)
        return week[weekday]
    }

    /// The next date on/after `from` that has a non-rest effective routine (scans up to 14 days).
    public static func nextTrainingDay(
        week: [Int: String],
        dayPlan: [String: String],
        from: Date,
        calendar: Calendar = .current,
        scanDays: Int = 14
    ) -> (date: Date, routineID: String)? {
        for offset in 0..<scanDays {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: from) else { continue }
            if let routineID = effectiveRoutineID(week: week, dayPlan: dayPlan, date: candidate, calendar: calendar) {
                return (date: candidate, routineID: routineID)
            }
        }
        return nil
    }
}
