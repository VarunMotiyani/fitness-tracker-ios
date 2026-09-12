import SwiftUI
import UIKit

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
            // Attach one lightweight recognizer to the containing window so a
            // tap anywhere outside a text editor/field dismisses the keyboard.
            // Keeping the recognizer at window level avoids adding competing
            // SwiftUI tap gestures to every form and preserves control taps.
            .background(WindowKeyboardDismissViewRepresentable())
            .scrollDismissesKeyboard(.interactively)
    }
}

/// A zero-size SwiftUI anchor that installs a tap recognizer on the current
/// UIWindow. The recognizer ignores touches that begin inside a text input so
/// moving between fields still works; all other taps resign the first
/// responder. This complements `.scrollDismissesKeyboard(.interactively)` for
/// forms with a large amount of empty space around the inputs.
private struct WindowKeyboardDismissViewRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> WindowKeyboardDismissView {
        WindowKeyboardDismissView()
    }

    func updateUIView(_ uiView: WindowKeyboardDismissView, context: Context) {}
}

private final class WindowKeyboardDismissView: UIView, UIGestureRecognizerDelegate {
    private weak var installedWindow: UIWindow?
    private var tapGesture: UITapGestureRecognizer?
    private var panGesture: UIPanGestureRecognizer?
    private var didDismissDuringPan = false

    override func didMoveToWindow() {
        super.didMoveToWindow()

        if let tapGesture, let installedWindow {
            installedWindow.removeGestureRecognizer(tapGesture)
        }
        if let panGesture, let installedWindow {
            installedWindow.removeGestureRecognizer(panGesture)
        }
        tapGesture = nil
        panGesture = nil
        installedWindow = window

        guard let window else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
        tapGesture = tap

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.cancelsTouchesInView = false
        pan.delegate = self
        window.addGestureRecognizer(pan)
        panGesture = pan
    }

    deinit {
        if let tapGesture, let installedWindow {
            installedWindow.removeGestureRecognizer(tapGesture)
        }
        if let panGesture, let installedWindow {
            installedWindow.removeGestureRecognizer(panGesture)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer is UITapGestureRecognizer else { return true }

        var view = touch.view
        while let current = view {
            if current is UITextField || current is UITextView {
                return false
            }
            view = current.superview
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // The window pan is only a keyboard-dismissal observer. Let the
        // underlying ScrollView/List keep handling the same drag normally.
        gestureRecognizer === panGesture || otherGestureRecognizer === panGesture
    }

    @objc private func handleTap() {
        dismissKeyboard()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            guard !didDismissDuringPan else { return }

            let translation = gesture.translation(in: gesture.view)
            let horizontalDistance = abs(translation.x)
            guard translation.y > 24,
                  translation.y > horizontalDistance * 1.15 else { return }

            didDismissDuringPan = true
            dismissKeyboard()
        case .ended, .cancelled, .failed:
            didDismissDuringPan = false
        default:
            break
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

extension View {
    /// Applies the app-wide iPhone keyboard contract to a form or input screen.
    func keyboardHandling() -> some View {
        modifier(KeyboardHandling())
    }
}
