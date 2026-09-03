import SwiftUI

public struct TimerFlashOverlay: View {
    public let triggerID: UUID?
    @State private var flashOpacity: Double = 0.0

    public init(triggerID: UUID?) {
        self.triggerID = triggerID
    }

    public var body: some View {
        Color.white
            .opacity(flashOpacity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .onChange(of: triggerID) { _, newTrigger in
                if newTrigger != nil {
                    pulseFlash()
                }
            }
    }

    private func pulseFlash() {
        withAnimation(.easeInOut(duration: 0.12).repeatCount(4, autoreverses: true)) {
            flashOpacity = 0.6
        } completion: {
            flashOpacity = 0.0
        }
    }
}
