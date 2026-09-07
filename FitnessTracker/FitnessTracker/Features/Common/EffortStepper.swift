import SwiftUI

public struct EffortStepper: View {
    @Binding public var value: Double?
    public let mode: String // "rir" or "rpe"

    public init(value: Binding<Double?>, mode: String = "rir") {
        self._value = value
        self.mode = mode
    }

    private var isRPE: Bool { mode.lowercased() == "rpe" }
    private var minVal: Double { isRPE ? 6.0 : 0.0 }
    private var maxVal: Double { 10.0 }
    private var step: Double { 0.5 }

    public var body: some View {
        HStack(spacing: 0) {
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                if let current = value {
                    if current - step < minVal {
                        value = nil
                    } else {
                        value = current - step
                    }
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Value Display
            HStack(spacing: 2) {
                if let v = value {
                    Text(String(format: "%.1f", v))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(GymTheme.green)
                        .monospacedDigit()
                        .lineLimit(1)
                } else {
                    Text("—")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(GymTheme.label3)
                }
            }
            .frame(maxWidth: .infinity)

            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                if let current = value {
                    value = min(maxVal, current + step)
                } else {
                    value = minVal
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: 36)
        .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 8))
    }
}
