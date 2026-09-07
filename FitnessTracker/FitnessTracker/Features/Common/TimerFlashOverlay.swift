import SwiftUI

public struct TimerFlashOverlay: View {
    public let triggerID: UUID?
    @State private var flashOpacity: Double = 0.0
    @State private var currentColor: Color = .clear
    @State private var animationTask: Task<Void, Never>?

    public init(triggerID: UUID?) {
        self.triggerID = triggerID
    }

    public var body: some View {
        currentColor
            .opacity(flashOpacity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .onChange(of: triggerID) { _, newTrigger in
                if newTrigger != nil {
                    startFourFlashSequence()
                }
            }
            .onDisappear {
                animationTask?.cancel()
            }
    }

    private func startFourFlashSequence() {
        animationTask?.cancel()
        animationTask = Task { @MainActor in
            // Timing matching openGym @keyframes timer-flash-four (2.4s total):
            // 4%,16%,60%,72% -> black flash
            // 32%,44%,88%,96% -> white flash
            let flashSteps: [(color: Color, gapMs: UInt64, durationMs: UInt64)] = [
                (.black, 96, 288),   // Flash 1: 4%..16% (96..384ms)
                (.white, 384, 288),  // Flash 2: 32%..44% (768..1056ms)
                (.black, 384, 288),  // Flash 3: 60%..72% (1440..1728ms)
                (.white, 384, 192)   // Flash 4: 88%..96% (2112..2304ms)
            ]

            for (idx, step) in flashSteps.enumerated() {
                // Gap before this flash
                currentColor = .clear
                flashOpacity = 0.0
                try? await Task.sleep(nanoseconds: step.gapMs * 1_000_000)
                if Task.isCancelled { return }

                // Active Flash
                currentColor = step.color
                withAnimation(.linear(duration: 0.04)) {
                    flashOpacity = 0.85
                }
                try? await Task.sleep(nanoseconds: step.durationMs * 1_000_000)
                if Task.isCancelled { return }
            }

            // Final gap to 100% (2400ms)
            withAnimation(.linear(duration: 0.08)) {
                flashOpacity = 0.0
            }
            try? await Task.sleep(nanoseconds: 96 * 1_000_000)
            if !Task.isCancelled {
                currentColor = .clear
                flashOpacity = 0.0
            }
        }
    }
}
