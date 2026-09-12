import Foundation

/// Plain-text chat export, shared by every place a conversation can be
/// exported (`ChatView`'s own header, `CoachInboxView`'s) — one formatting
/// rule to keep in sync, not two copies that quietly drift apart.
enum ChatTranscriptExporter {
    static func text(for messages: [ChatMessageModel]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let lines = messages.map { message -> String in
            let who = message.role == "user" ? "You" : "Coach"
            let body = message.text.isEmpty ? (cardSummary(for: message) ?? "") : message.text
            return "[\(formatter.string(from: message.timestamp))] \(who): \(body)"
        }
        return lines.joined(separator: "\n\n")
    }

    private static func cardSummary(for message: ChatMessageModel) -> String? {
        guard let kind = message.cardKind else { return nil }
        switch kind {
        case .suggestion:
            return "[Card: suggestion pending review]"
        case .appliedChange:
            guard let payload = message.decodedCardPayload(as: AppliedChangeCardPayload.self) else { return nil }
            return "[Card: \(payload.title) — \(payload.detail)]"
        case .planRegeneration:
            guard let payload = message.decodedCardPayload(as: PlanRegenerationCardPayload.self) else { return nil }
            return "[Card: plan regeneration — \(payload.status.rawValue)\(payload.detail.map { " (\($0))" } ?? "")]"
        case .startWorkout:
            guard let payload = message.decodedCardPayload(as: StartWorkoutCardPayload.self) else { return nil }
            return "[Card: start workout — \(payload.sessionName)]"
        }
    }

    /// Writes the transcript to a temp file ready to hand to `ShareSheet`.
    /// `nil` only on a write failure (disk full, etc.) — the caller shows
    /// that as an error rather than silently doing nothing.
    static func writeToTempFile(_ messages: [ChatMessageModel]) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let filename = "coach-chat-\(formatter.string(from: .now)).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try text(for: messages).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
