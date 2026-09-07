import Foundation

public enum BackfillOps {
    /// Epoch for `date` at wall-clock `time` (default 18:00), local zone
    public static func startInstant(date: DateComponents, time: (h: Int, m: Int) = (18, 0), calendar: Calendar = .current) -> Date {
        var comps = date
        comps.hour = time.h
        comps.minute = time.m
        comps.second = 0
        return calendar.date(from: comps) ?? Date()
    }

    /// end = start + max(1, durationMin) * 60
    public static func endInstant(start: Date, durationMin: Int) -> Date {
        let mins = max(1, durationMin)
        return start.addingTimeInterval(Double(mins * 60))
    }

    /// Insert `session` into a chronological [CompletedSessionSnapshot] by (date)
    public static func insertChronological(
        _ sessions: [CompletedSessionSnapshot],
        _ session: CompletedSessionSnapshot
    ) -> [CompletedSessionSnapshot] {
        var list = sessions
        list.append(session)
        return list.sorted { $0.date < $1.date }
    }

    /// Drop `replaceID` (if any), then insert chronologically.
    public static func commit(
        _ sessions: [CompletedSessionSnapshot],
        _ session: CompletedSessionSnapshot,
        replaceID: UUID?
    ) -> [CompletedSessionSnapshot] {
        var list = sessions
        if let replaceID = replaceID {
            list.removeAll { $0.id == replaceID }
        }
        list.append(session)
        return list.sorted { $0.date < $1.date }
    }
}
