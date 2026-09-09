import Foundation

public extension Calendar {
    /// The app's day/week bucketing calendar. ISO-8601 week rules (weeks start
    /// Monday, `minimumDaysInFirstWeek == 4`) but anchored to the **device's own
    /// time zone**, so "today" and week boundaries follow the phone the user is
    /// holding — travel and DST are picked up automatically via
    /// `TimeZone.autoupdatingCurrent`.
    static let appWeek: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = .autoupdatingCurrent
        return c
    }()
}
