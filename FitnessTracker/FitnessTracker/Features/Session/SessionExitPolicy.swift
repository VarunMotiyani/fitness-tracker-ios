import Foundation

/// Close behavior is intentionally different for setup and active workout:
/// setup is frictionless, while an active workout asks for confirmation.
enum SessionExitPolicy {
    nonisolated static let startScreenRequiresConfirmation = false
    nonisolated static let activeWorkoutRequiresConfirmation = true
}
