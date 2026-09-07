import SwiftUI
import AudioToolbox
#if canImport(UIKit)
import UIKit
#endif

/// A countdown between working sets. `SessionFocusView` owns one instance and
/// calls `start(seconds:)` after each logged set. The per-second decrement is
/// factored into `tick()` so unit tests can drive it synchronously without
/// waiting a real second.
@MainActor
@Observable
final class RestTimer {
    private(set) var remaining: Int = 0
    private(set) var isRunning: Bool = false
    /// The value `start(seconds:)` was called with — used for the ring fraction.
    private(set) var total: Int = 0
    /// Wall-clock moment the current countdown began — drives `elapsed`.
    private(set) var startedAt: Date?
    /// Callback invoked when timer hits zero.
    var onComplete: (() -> Void)?

    private var timer: Timer?

    // No `deinit { timer?.invalidate() }`: Swift 6 rejects touching the
    // main-actor-isolated `timer` from the nonisolated `deinit`
    // ("main actor-isolated property 'timer' can not be referenced from a
    // nonisolated context"). The `[weak self]` guard in `scheduleTimer`
    // self-heals the dangling timer on its next tick.

    /// Real wall-clock rest taken so far, regardless of skip/add adjustments.
    /// Zero when the timer has never been started (first set of an entry).
    var elapsed: Int {
        guard let startedAt else { return 0 }
        return max(0, Int(Date().timeIntervalSince(startedAt)))
    }

    /// Begin (or restart) a countdown of `seconds` seconds.
    func start(seconds: Int) {
        stopTimer()
        total = max(0, seconds)
        remaining = total
        isRunning = total > 0
        startedAt = Date()
        guard isRunning else { return }
        scheduleTimer()
    }

    /// Add (or subtract) time. Clamps at zero. Subtracting to zero stops the
    /// countdown and fires the completion haptic; adding back above zero resumes.
    func add(_ delta: Int) {
        remaining = max(0, remaining + delta)
        if remaining == 0 {
            isRunning = false
            stopTimer()
            fireCompletionFeedback()
            onComplete?()
        } else if !isRunning {
            isRunning = true
            scheduleTimer()
        }
    }

    /// Manual skip — no haptic.
    func skip() {
        remaining = 0
        isRunning = false
        stopTimer()
    }

    /// The per-second decrement. Called by the scheduled timer and, directly,
    /// by unit tests. Never goes negative; handles the zero transition once.
    func tick() {
        guard remaining > 0 else {
            remaining = 0
            isRunning = false
            stopTimer()
            return
        }
        remaining -= 1
        if remaining > 0 && remaining <= 3 {
            fireWarningSound()
        }
        if remaining <= 0 {
            remaining = 0
            isRunning = false
            stopTimer()
            fireCompletionFeedback()
            onComplete?()
        }
    }

    // MARK: - Timer plumbing

    private func scheduleTimer() {
        // Scheduled on the main run loop (start() is @MainActor), so the callback
        // fires on the main thread — invalidate/tick here are main-thread safe.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            MainActor.assumeIsolated { self.tick() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func isSoundEnabled() -> Bool {
        UserDefaults.standard.object(forKey: "gym_sound") as? Bool ?? true
    }

    private func fireWarningSound() {
        if isSoundEnabled() {
            AudioServicesPlaySystemSound(1052)
        }
    }

    private func fireCompletionFeedback() {
        if isSoundEnabled() {
            AudioServicesPlaySystemSound(1005)
        }
        // TODO(phase4): local notification when backgrounded
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

/// Compact circular countdown with −30s / +30s / Skip controls. Renders inside
/// `SessionFocusView`, not full-screen.
struct RestTimerView: View {
    let timer: RestTimer

    private var fraction: Double {
        timer.total > 0 ? Double(timer.remaining) / Double(timer.total) : 0
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Rest")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                Circle()
                    .stroke(Color(.tertiarySystemBackground), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: timer.remaining)
                Text("\(timer.remaining)s")
                    .font(.title2.weight(.semibold).monospacedDigit())
            }
            .frame(width: 96, height: 96)

            HStack(spacing: 12) {
                Button("−30s") { timer.add(-30) }
                Button("+30s") { timer.add(30) }
                Button("Skip") { timer.skip() }
            }
            .buttonStyle(.bordered)
            .font(.subheadline)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }
}

#Preview {
    let t = RestTimer()
    t.start(seconds: 90)
    return RestTimerView(timer: t).padding()
}
