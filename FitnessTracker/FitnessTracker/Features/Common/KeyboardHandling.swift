import SwiftUI

/// Shared iPhone keyboard behavior for every input surface.
///
/// SwiftUI keeps a keyboard visible after a field loses visual prominence and
/// numeric keyboards have no Return/Done key. This modifier keeps dismissal
/// gesture-first: a user can drag the form to dismiss without adding a
/// floating accessory control. The system still owns keyboard insets and focus
/// scrolling; we do not hard-code keyboard heights.
struct KeyboardHandling: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
    }
}

extension View {
    /// Applies the app-wide iPhone keyboard contract to a form or input screen.
    func keyboardHandling() -> some View {
        modifier(KeyboardHandling())
    }
}
