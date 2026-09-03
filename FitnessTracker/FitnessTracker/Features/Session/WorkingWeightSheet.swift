import SwiftUI
import ExerciseCatalog

public struct WorkingWeightSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let exerciseName: String
    public let exerciseID: String
    public let initialWeight: Double
    public let previousBest: Double?
    public let onSave: (Double) -> Void

    @State private var weight: Double

    public init(
        exerciseName: String,
        exerciseID: String,
        initialWeight: Double,
        previousBest: Double?,
        onSave: @escaping (Double) -> Void
    ) {
        self.exerciseName = exerciseName
        self.exerciseID = exerciseID
        self.initialWeight = initialWeight
        self.previousBest = previousBest
        self.onSave = onSave
        self._weight = State(initialValue: initialWeight)
    }

    private var isNewRecord: Bool {
        if let prev = previousBest, prev > 0 {
            return weight > prev
        }
        return false
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(GymTheme.green)

                    Text("\(exerciseName) Completed!")
                        .font(.title3.bold())
                        .foregroundStyle(GymTheme.label)

                    Text("Confirm your working weight for next session's recommendations:")
                        .font(.subheadline)
                        .foregroundStyle(GymTheme.label2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .padding(.top, 16)

                if isNewRecord {
                    HStack(spacing: 6) {
                        Image(systemName: "trophy.fill")
                            .foregroundStyle(GymTheme.orange)
                        Text("New Personal Record!")
                            .font(.caption.bold())
                            .foregroundStyle(GymTheme.orange)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(GymTheme.orange.opacity(0.15), in: Capsule())
                }

                HStack(spacing: 8) {
                    TextField("0.0", value: $weight, format: .number)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 140)
                    Text("kg")
                        .font(.title2.bold())
                        .foregroundStyle(GymTheme.label3)
                }
                .padding(.vertical, 10)

                Spacer()

                Button {
                    onSave(weight)
                    dismiss()
                } label: {
                    Text("Save & Next")
                        .font(.headline)
                        .foregroundStyle(GymTheme.bg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(GymTheme.green, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .background(GymTheme.bg.ignoresSafeArea())
            .navigationTitle("Working Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
