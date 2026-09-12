import Foundation
import SwiftData

/// One turn in the Ask Coach transcript. `role` is `"user"` or `"assistant"`.
@Model
final class ChatMessageModel {
    var id: UUID
    /// Conversation partition. Existing rows default to the original
    /// conversation so this is an additive SwiftData migration.
    var conversationID: String = "default"
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
         conversationID: String = "default",
         cardKindRaw: String? = nil, cardPayloadJSON: String? = nil) {
        self.id = UUID()
        self.conversationID = conversationID
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.cardKindRaw = cardKindRaw
        self.cardPayloadJSON = cardPayloadJSON
    }
}

/// One conversation's rolling fold of everything older than its last ~10
/// `ChatMessageModel` rows. Empty `text` until the first fold happens.
@Model
final class ChatSummaryModel {
    var conversationID: String = "default"
    var text: String
    var updatedAt: Date
    /// The newest message's timestamp already folded in — the next
    /// summarization pass only needs to fold messages after this.
    var messagesCoveredThrough: Date?

    init(conversationID: String = "default") {
        self.conversationID = conversationID
        self.text = ""
        self.updatedAt = .now
        self.messagesCoveredThrough = nil
    }
}
