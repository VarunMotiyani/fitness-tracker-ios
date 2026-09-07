import Foundation
import SwiftData

/// One turn in the Ask Coach transcript. `role` is `"user"` or `"assistant"`.
@Model
final class ChatMessageModel {
    var id: UUID
    var role: String
    var text: String
    var timestamp: Date

    init(role: String, text: String, timestamp: Date = .now) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

/// Singleton row: the rolling fold of everything older than the last ~10
/// `ChatMessageModel` rows (design spec §2). Empty `text` until the first
/// fold happens.
@Model
final class ChatSummaryModel {
    var text: String
    var updatedAt: Date
    /// The newest message's timestamp already folded in — the next
    /// summarization pass only needs to fold messages after this.
    var messagesCoveredThrough: Date?

    init() {
        self.text = ""
        self.updatedAt = .now
        self.messagesCoveredThrough = nil
    }
}
