import SwiftUI

/// openGym tactile gym-floor stepper with minus/plus buttons and centered editable value.
struct GymStepper: View {
    @Binding var value: Double
    let step: Double
    let minVal: Double
    let maxVal: Double
    let unit: String?
    let isDecimal: Bool

    init(
        value: Binding<Double>,
        step: Double = 2.5,
        minVal: Double = 0.0,
        maxVal: Double = 500.0,
        unit: String? = "kg",
        isDecimal: Bool = true
    ) {
        self._value = value
        self.step = step
        self.minVal = minVal
        self.maxVal = maxVal
        self.unit = unit
        self.isDecimal = isDecimal
    }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                value = max(minVal, value - step)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Centered Value
            HStack(spacing: 2) {
                Text(isDecimal ? String(format: "%.1f", value) : "\(Int(value))")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                if let unit {
                    Text(unit)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color(white: 0.6))
                }
            }
            .frame(maxWidth: .infinity)

            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                value = min(maxVal, value + step)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: 38)
        .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 10))
    }
}
