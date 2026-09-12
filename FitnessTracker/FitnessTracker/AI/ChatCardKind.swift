import Foundation

/// What structured UI a `ChatMessageModel` renders instead of (or alongside)
/// plain text. `nil` on the model itself means "just text" — the default,
/// unchanged path every pre-existing message still takes.
enum ChatCardKind: String, Codable {
    /// A proposal awaiting Accept/Skip — the same `PendingCoachSuggestion`
    /// `SuggestionCard` already renders on Home, now also inline in chat.
    case suggestion
    /// A direct-action tool (apply_*, log_bodyweight, set_day_to_rest)
    /// already completed — a compact confirmation, not a card needing input.
    case appliedChange
    /// `regenerate_plan`'s lifecycle: inserted `.pending` immediately, then
    /// mutated in place to `.succeeded`/`.failed` once generation finishes —
    /// replaces appending the outcome note onto the reply's own text.
    case planRegeneration
    /// `start_workout` — a session name/action instead of a silent side effect.
    case startWorkout
}

struct SuggestionCardPayload: Codable {
    let suggestionID: UUID
}

struct AppliedChangeCardPayload: Codable {
    let icon: String
    let title: String
    let detail: String
}

enum PlanRegenerationStatus: String, Codable {
    case pending, succeeded, failed
}

struct PlanRegenerationCardPayload: Codable {
    var status: PlanRegenerationStatus
    /// Set once `status` leaves `.pending` — `GenerationOutcome.note`, or a
    /// failure description.
    var detail: String?
}

struct StartWorkoutCardPayload: Codable {
    let plannedSessionID: UUID
    let sessionName: String
}

extension ChatMessageModel {
    var cardKind: ChatCardKind? {
        get { cardKindRaw.flatMap(ChatCardKind.init(rawValue:)) }
        set { cardKindRaw = newValue?.rawValue }
    }

    func decodedCardPayload<T: Decodable>(as type: T.Type) -> T? {
        guard let json = cardPayloadJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func setCardPayload<T: Encodable>(_ payload: T) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        cardPayloadJSON = String(data: data, encoding: .utf8)
    }
}
