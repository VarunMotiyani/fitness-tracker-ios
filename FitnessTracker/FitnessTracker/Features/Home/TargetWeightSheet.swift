import SwiftUI

struct TargetWeightSheet: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("gym_accent_color") private var accentColorKey: String = "lime"
    private var activeAccent: Color { GymTheme.accent(for: accentColorKey) }

    @State private var targetWeight: Double
    let initialTarget: Double?
    var onSave: (Double) -> Void
    var onRemove: () -> Void

    init(targetWeight: Double? = 77.0, onSave: @escaping (Double) -> Void, onRemove: @escaping () -> Void) {
        self.initialTarget = targetWeight
        _targetWeight = State(initialValue: targetWeight ?? 77.0)
        self.onSave = onSave
        self.onRemove = onRemove
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                // Title
                Text("Target weight")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(GymTheme.label)

                // Subtitle
                Text("Your goal is drawn as a line through the weight charts, and gains/losses are colored by whether they move toward it.")
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(Color(white: 0.60))
                    .lineSpacing(2)

                // Stepper & Slider
                WeightInputView(value: $targetWeight, unit: "kg", minVal: 30.0, maxVal: 200.0, isInteger: true)
                    .padding(.vertical, 4)

                // Save Goal Button
                Button {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    onSave(targetWeight)
                    dismiss()
                } label: {
                    Text("Save goal")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(activeAccent, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)

                // Remove Goal Button (if goal was previously set)
                if initialTarget != nil {
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        onRemove()
                        dismiss()
                    } label: {
                        Text("Remove goal")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(GymTheme.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color(red: 0.20, green: 0.08, blue: 0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 20)
            .background(GymTheme.bgElevated.ignoresSafeArea())
        }
        .presentationDetents([.height(initialTarget != nil ? 380 : 320)])
        .presentationDragIndicator(.visible)
    }
}
