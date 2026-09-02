import SwiftUI
import SwiftData

struct LogWeightSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \BodyweightEntryModel.date, order: .reverse)
    private var entries: [BodyweightEntryModel]

    @State private var weight: Double
    var onSaved: ((Double) -> Void)? = nil

    init(initialWeight: Double = 78.7, onSaved: ((Double) -> Void)? = nil) {
        _weight = State(initialValue: initialWeight)
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                // Title
                Text("Log body weight")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(GymTheme.label)

                // Subtitle
                Text("Today, \(Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color(white: 0.60))

                // Stepper & Slider
                WeightInputView(value: $weight, unit: "kg", minVal: 30.0, maxVal: 200.0, isInteger: false)
                    .padding(.vertical, 4)

                // Save Button
                Button {
                    saveWeight()
                } label: {
                    Text("Save")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(GymTheme.green, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)

                // Recent weigh-ins
                if !entries.isEmpty {
                    Text("Recent weigh-ins")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(white: 0.50))
                        .padding(.top, 14)

                    VStack(spacing: 0) {
                        ForEach(Array(entries.prefix(4).enumerated()), id: \.element.id) { idx, item in
                            HStack {
                                Text(item.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(Color(white: 0.65))

                                Spacer()

                                Text(String(format: "%.1f kg", item.kg))
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(GymTheme.label)

                                Button {
                                    deleteEntry(item)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 14))
                                        .foregroundStyle(GymTheme.red)
                                        .frame(width: 32, height: 32)
                                        .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, 8)
                            }
                            .padding(.vertical, 10)

                            if idx < min(3, entries.count - 1) {
                                Divider()
                                    .background(Color.white.opacity(0.06))
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .background(GymTheme.bgElevated.ignoresSafeArea())
        }
        .presentationDetents([.fraction(0.68), .large])
        .presentationDragIndicator(.visible)
    }

    private func saveWeight() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        let entry = BodyweightEntryModel(date: .now, kg: weight)
        context.insert(entry)
        try? context.save()
        onSaved?(weight)
        dismiss()
    }

    private func deleteEntry(_ entry: BodyweightEntryModel) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        context.delete(entry)
        try? context.save()
    }
}
