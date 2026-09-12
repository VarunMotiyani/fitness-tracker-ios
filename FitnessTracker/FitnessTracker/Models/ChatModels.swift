import Foundation
import SwiftData

/// One turn in the Ask Coach transcript. `role` is `"user"` or `"assistant"`.
@Model
final class ChatMessageModel {
    var id: UUID
    var role: String
    var text: String
    var timestamp: Date
    /// Raw `ChatCardKind`. `nil` (the default for every pre-existing row) means
    /// this message renders as plain text, same as always — a card is opt-in
    /// per message, never a required field, so this is a safe additive
    /// SwiftData migration.
    var cardKindRaw: String?
    /// JSON payload for `cardKindRaw`'s shape — see `ChatCardKind` for which
    /// struct decodes it. `nil` alongside `cardKindRaw == nil`.
    var cardPayloadJSON: String?

    init(role: String, text: String, timestamp: Date = .now,
         cardKindRaw: String? = nil, cardPayloadJSON: String? = nil) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.cardKindRaw = cardKindRaw
        self.cardPayloadJSON = cardPayloadJSON
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
