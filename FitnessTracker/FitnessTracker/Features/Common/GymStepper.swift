import SwiftUI

/// Tactile gym-floor stepper with minus/plus buttons and centered value.
/// Buttons are 44×44 hit targets (HIG minimum) — the visual capsule is the
/// same height so rows never reflow. The ± glyph stays fixed-size on purpose
/// (it is an icon, not text-flow); the value follows Dynamic Type.
struct GymStepper: View {
    @Binding var value: Double
    let step: Double
    let minVal: Double
    let maxVal: Double
    let unit: String?
    let isDecimal: Bool
    var a11yLabel: String?

    init(
        value: Binding<Double>,
        step: Double = 2.5,
        minVal: Double = 0.0,
        maxVal: Double = 500.0,
        unit: String? = "kg",
        isDecimal: Bool = true,
        a11yLabel: String? = nil
    ) {
        self._value = value
        self.step = step
        self.minVal = minVal
        self.maxVal = maxVal
        self.unit = unit
        self.isDecimal = isDecimal
        self.a11yLabel = a11yLabel
    }

    private var unitName: String { unit ?? "value" }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                bump(-step)
            } label: {
                Image(systemName: "minus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(a11yLabel.map { "Decrease \($0)" } ?? "Decrease \(unitName)")

            // Centered Value
            HStack(spacing: 1) {
                Text(isDecimal ? String(format: "%.1f", value) : "\(Int(value))")
                    .font(.subheadline.weight(.semibold)).fontDesign(.rounded)
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let unit {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(Color(white: 0.6))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)

            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                bump(step)
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(a11yLabel.map { "Increase \($0)" } ?? "Increase \(unitName)")
        }
        .frame(height: 44)
        .background(Color(white: 0.60), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            Text((isDecimal ? String(format: "%.1f", value) : "\(Int(value))")) + Text(" \(unitName)")
        )
    }

    private func bump(_ delta: Double) {
        value = min(maxVal, max(minVal, value + delta))
    }
}
