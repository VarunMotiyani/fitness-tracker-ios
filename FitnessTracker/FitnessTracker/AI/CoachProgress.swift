import Foundation
import Combine

/// Live status text for the current Ask Coach turn's tool-call loop —
/// "Checking your schedule…", "Starting your workout…" — instead of a single
/// static "Coach is thinking…" no matter how many sequential tool calls a
/// turn actually takes. `ChatView` observes this while `send()` is in
/// flight; it's purely cosmetic and never read by anything that decides
/// what the coach actually does.
@MainActor
final class CoachProgress: ObservableObject {
    @Published var stepText: String?
}
