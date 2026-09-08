import Foundation
import SwiftData

/// A proactive message from the coach (design spec §5). `kindRaw` is
/// `"daily"` | `"weekly"` | `"checkin"` | `"pattern"`. Daily and weekly rows
/// are replaced for the current period; reactive rows retain their history.
@Model
final class CoachNoteModel {
    var id: UUID
    var kindRaw: String
    var topicRaw: String?
    var text: String
    var reason: String?
    var createdAt: Date
    var readAt: Date?

    init(kindRaw: String, text: String, reason: String? = nil, topicRaw: String? = nil, createdAt: Date = .now) {
        self.id = UUID()
        self.kindRaw = kindRaw
        self.topicRaw = topicRaw
        self.text = text
        self.reason = reason
        self.createdAt = createdAt
        self.readAt = nil
    }
}

/// One generated weekly recap (design spec §5). One row per ISO week; a
/// regeneration overwrites the existing row for that week.
@Model
final class WeeklySummaryModel {
    var weekStartDate: Date
    var headline: String
    var summaryBody: String
    var nextWeekFocus: String
    var generatedAt: Date

    init(weekStartDate: Date, headline: String, summaryBody: String, nextWeekFocus: String) {
        self.weekStartDate = weekStartDate
        self.headline = headline
        self.summaryBody = summaryBody
        self.nextWeekFocus = nextWeekFocus
        self.generatedAt = .now
    }
}
