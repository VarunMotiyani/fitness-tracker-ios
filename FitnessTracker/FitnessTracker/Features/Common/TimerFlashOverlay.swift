import SwiftUI
import UIKit

/// Rest-timer-end screen cue. Two black pulses at reduced amplitude — the
/// old sequence was four alternating black/white pulses at 85% opacity
/// (~4 Hz), which is a photosensitivity hazard. With Reduce Motion on, the
/// strobe is suppressed entirely and replaced with a single non-flashing
/// tint + a success haptic — a cue still fires, it just never pulses.
public struct TimerFlashOverlay: View {
    public let triggerID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flashOpacity: Double = 0.0
    @State private var animationTask: Task<Void, Never>?

    public init(triggerID: UUID?) {
        self.triggerID = triggerID
    }

    public var body: some View {
        Color.black
            .opacity(flashOpacity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .onChange(of: triggerID) { _, newTrigger in
                guard newTrigger != nil else { return }
                reduceMotion ? startReducedMotionCue() : startFlashSequence()
            }
            .onDisappear {
                animationTask?.cancel()
            }
    }

    /// Reduce Motion fallback: one 200ms non-repeating tint, well under
    /// strobe territory, plus the haptic doing the actual cueing.
    private func startReducedMotionCue() {
        animationTask?.cancel()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        animationTask = Task { @MainActor in
            withAnimation(.linear(duration: 0.1)) { flashOpacity = 0.25 }
            try? await Task.sleep(nanoseconds: 200 * 1_000_000)
            if Task.isCancelled { return }
            withAnimation(.linear(duration: 0.1)) { flashOpacity = 0.0 }
        }
    }

    private func startFlashSequence() {
        animationTask?.cancel()
        animationTask = Task { @MainActor in
            // Two black pulses: 0.35 peak, ~170 ms each, 260 ms gap (~0.9 s total).
            let pulseMs: UInt64 = 170
            let gapMs: UInt64 = 260
            for _ in 0..<2 {
                withAnimation(.linear(duration: 0.04)) {
                    flashOpacity = 0.35
                }
                try? await Task.sleep(nanoseconds: pulseMs * 1_000_000)
                if Task.isCancelled { return }
                withAnimation(.linear(duration: 0.08)) {
                    flashOpacity = 0.0
                }
                try? await Task.sleep(nanoseconds: gapMs * 1_000_000)
                if Task.isCancelled { return }
            }
        }
    }
}
