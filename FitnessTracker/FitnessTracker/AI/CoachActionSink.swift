import Foundation

/// Bridges a tool-triggered side effect out of the tool loop and into
/// `AskCoachCoordinator.send()`'s result. `CoachTool.run` is synchronous and
/// can only return a string back to the model — it has no way to reach the
/// SwiftUI layer (start a session) or do async work (regenerate a plan).
/// Tools that need either just record the request here; the coordinator
/// (plan regeneration, which it can `await` itself) or the caller (session
/// start, via `AskCoachReply.startSessionID`) is what actually acts on it.
@MainActor
final class CoachActionSink {
    private(set) var startSessionID: UUID?
    private(set) var requestedPlanRegeneration = false

    func requestStartSession(_ id: UUID) { startSessionID = id }
    func requestPlanRegeneration() { requestedPlanRegeneration = true }
}
