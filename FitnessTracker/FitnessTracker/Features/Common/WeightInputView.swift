import SwiftUI

struct WeightInputView: View {
    @Binding var value: Double
    let unit: String
    let minVal: Double
    let maxVal: Double
    let isInteger: Bool

    init(value: Binding<Double>, unit: String = "kg", minVal: Double = 30.0, maxVal: Double = 250.0, isInteger: Bool = false) {
        self._value = value
        self.unit = unit
        self.minVal = minVal
        self.maxVal = maxVal
        self.isInteger = isInteger
    }

    var body: some View {
        VStack(spacing: 12) {
            // Main Stepper: [-] 78.7 kg [+]
            HStack(spacing: 20) {
                Button {
                    step(by: -0.1)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(GymTheme.surface2, in: Circle())
                }
                .buttonStyle(.plain)

                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(isInteger ? String(format: "%.0f", value) : String(format: "%.1f", value))
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(GymTheme.label)
                        .monospacedDigit()
                    Text(unit)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color(white: 0.60))
                }
                .frame(minWidth: 160)

                Button {
                    step(by: +0.1)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(GymTheme.surface2, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)

            // Increment Chips: [-1] [-0.5] [+0.5] [+1]
            HStack(spacing: 10) {
                chipButton(label: "−1", delta: -1.0)
                chipButton(label: "−0.5", delta: -0.5)
                chipButton(label: "+0.5", delta: +0.5)
                chipButton(label: "+1", delta: +1.0)
            }

            // Slider
            Slider(value: $value, in: minVal...maxVal, step: 0.5)
                .tint(GymTheme.green)
                .padding(.horizontal, 4)
                .padding(.top, 2)
        }
    }

    private func step(by delta: Double) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        let raw = value + delta
        let rounded = (raw * 10).rounded() / 10
        value = max(minVal, min(maxVal, rounded))
    }

    @ViewBuilder
    private func chipButton(label: String, delta: Double) -> some View {
        Button {
            step(by: delta)
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GymTheme.label)
                .frame(width: 60, height: 34)
                .background(GymTheme.surface2, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
