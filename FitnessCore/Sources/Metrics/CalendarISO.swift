import Foundation

public extension Calendar {
    /// ISO-8601 week semantics in UTC — the default bucketing calendar so
    /// `weekStart` does not depend on the running device's locale or time zone.
    static let isoUTC: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
}
