import Foundation

/// Bridges a tool-triggered side effect out of the tool loop and into
/// `AskCoachCoordinator.send()`'s result. `CoachTool.run` is synchronous and
/// can only return a string back to the model — it has no way to do async
/// work itself (regenerate a plan needs the network). A tool that needs that
/// just records the request here; the coordinator, already in an async
/// context, is what actually awaits it.
///
/// Also collects card requests: a tool that completed a structured, real
/// action (applied a change, proposed one, offered to start a workout)
/// records what happened here instead of only describing it in the model's
/// own prose — `send()` turns each into its own `ChatMessageModel` row so the
/// transcript shows a real card (with its own button where one makes sense,
/// e.g. `start_workout`'s "Start Now"), not just a sentence claiming
/// something happened or a silent side effect the athlete didn't ask for yet.
@MainActor
final class CoachActionSink {
    private(set) var requestedPlanRegeneration = false
    private(set) var cardRequests: [(kind: ChatCardKind, payloadJSON: String)] = []

    func requestPlanRegeneration() { requestedPlanRegeneration = true }

    func addCard<T: Encodable>(_ kind: ChatCardKind, payload: T) {
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8)
        else { return }
        cardRequests.append((kind, json))
    }
}
