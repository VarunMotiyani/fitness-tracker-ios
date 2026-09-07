import SwiftUI

struct WeightInputView: View {
    @Binding var value: Double
    let unit: String
    let minVal: Double
    let maxVal: Double
    let isInteger: Bool

    @AppStorage("gym_accent_color") private var accentColorKey: String = "lime"
    private var activeAccent: Color { GymTheme.accent(for: accentColorKey) }

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
                    step(by: isInteger ? -1.0 : -0.1)
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
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(GymTheme.label)
                        .monospacedDigit()
                    Text(unit)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color(white: 0.60))
                }
                .frame(minWidth: 160)

                Button {
                    step(by: isInteger ? +1.0 : +0.1)
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

            // Increment Chips — whole-number jumps when the display itself only
            // ever shows whole numbers; a "+0.5" chip that visibly does nothing
            // (or silently jumps a whole kg) is worse than not offering it.
            HStack(spacing: 10) {
                if isInteger {
                    chipButton(label: "−5", delta: -5.0)
                    chipButton(label: "−1", delta: -1.0)
                    chipButton(label: "+1", delta: +1.0)
                    chipButton(label: "+5", delta: +5.0)
                } else {
                    chipButton(label: "−1", delta: -1.0)
                    chipButton(label: "−0.5", delta: -0.5)
                    chipButton(label: "+0.5", delta: +0.5)
                    chipButton(label: "+1", delta: +1.0)
                }
            }

            // Slider
            Slider(value: $value, in: minVal...maxVal, step: isInteger ? 1.0 : 0.5)
                .tint(activeAccent)
                .padding(.horizontal, 4)
                .padding(.top, 2)
        }
    }

    private func step(by delta: Double) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        let raw = value + delta
        // Round to whatever precision is actually displayed — otherwise a fractional
        // step (the ±0.5 chips, or the slider) can leave the stored value off by a
        // few tenths that never show up on screen (isInteger's "%.0f" hides them),
        // making a later ±1 tap look like it did nothing when it just crossed the
        // same rounded display value.
        let rounded = isInteger ? raw.rounded() : (raw * 10).rounded() / 10
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
