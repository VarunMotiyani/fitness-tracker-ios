import SwiftUI
import SwiftData
import Metrics

struct LogWeightSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \BodyweightEntryModel.date, order: .reverse)
    private var entries: [BodyweightEntryModel]

    @AppStorage("gym_accent_color") private var accentColorKey: String = "lime"
    private var activeAccent: Color { GymTheme.accent(for: accentColorKey) }

    @State private var weight: Double
    var onSaved: ((Double) -> Void)? = nil

    init(initialWeight: Double = 78.7, onSaved: ((Double) -> Void)? = nil) {
        _weight = State(initialValue: initialWeight)
        self.onSaved = onSaved
    }

    private var recentEntries: [BodyweightEntryModel] {
        Array(entries.prefix(3))
    }

    private var calculatedHeight: CGFloat {
        if recentEntries.isEmpty {
            return 370
        } else {
            return 360 + CGFloat(recentEntries.count) * 54
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Drag Indicator spacing + Title
            VStack(alignment: .leading, spacing: 4) {
                Text("Log body weight")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(GymTheme.label)

                Text("Today, \(Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color(white: 0.60))
            }
            .padding(.top, 28)

            // Stepper & Slider
            WeightInputView(value: $weight, unit: "kg", minVal: 30.0, maxVal: 200.0, isInteger: false)
                .padding(.vertical, 4)

            // Save Button
            Button {
                saveWeight()
            } label: {
                Text("Save")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(activeAccent, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            // Recent weigh-ins (historical records)
            if !recentEntries.isEmpty {
                Text("Recent weigh-ins")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(white: 0.50))
                    .padding(.top, 10)

                VStack(spacing: 0) {
                    ForEach(Array(recentEntries.enumerated()), id: \.element.id) { idx, item in
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
                                    .font(.system(size: 13))
                                    .foregroundStyle(GymTheme.red)
                                    .frame(width: 32, height: 30)
                                    .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 8)
                        }
                        .padding(.vertical, 9)

                        if idx < recentEntries.count - 1 {
                            Divider()
                                .background(Color.white.opacity(0.08))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .background(GymTheme.bgElevated.ignoresSafeArea())
        .onAppear {
            seedEntriesIfEmpty()
        }
        .presentationDetents([.height(calculatedHeight)])
        .presentationDragIndicator(.visible)
    }

    private func seedEntriesIfEmpty() {
        if entries.isEmpty {
            let cal = Calendar.isoUTC
            let now = Date()
            let e1 = BodyweightEntryModel(date: cal.date(byAdding: .day, value: -3, to: now) ?? now, kg: 78.7)
            let e2 = BodyweightEntryModel(date: cal.date(byAdding: .day, value: -7, to: now) ?? now, kg: 78.3)
            let e3 = BodyweightEntryModel(date: cal.date(byAdding: .day, value: -10, to: now) ?? now, kg: 78.8)
            context.insert(e1)
            context.insert(e2)
            context.insert(e3)
            try? context.save()
        }
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
