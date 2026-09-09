import SwiftUI
import SwiftData
import Metrics

struct LogWeightSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \BodyweightEntryModel.date, order: .reverse)
    private var entries: [BodyweightEntryModel]

    @Query(sort: \UserProfile.updatedAt, order: .reverse)
    private var profiles: [UserProfile]

    @AppStorage("gym_accent_color") private var accentColorKey: String = "lime"
    private var activeAccent: Color { GymTheme.accent(for: accentColorKey) }

    @State private var weight: Double
    @State private var selectedSlot: BodyweightReadingSlot
    @State private var savedSummary: String?
    var onSaved: ((Double) -> Void)? = nil

    init(initialWeight: Double = 78.7, onSaved: ((Double) -> Void)? = nil) {
        _weight = State(initialValue: initialWeight)
        let hour = Calendar.appWeek.component(.hour, from: .now)
        _selectedSlot = State(initialValue: hour < 15 ? .morning : .night)
        self.onSaved = onSaved
    }

    private var recentEntries: [BodyweightEntryModel] {
        Array(entries.prefix(3))
    }

    private var todayEntry: BodyweightEntryModel? {
        entries.first { Calendar.appWeek.isDate($0.date, inSameDayAs: .now) }
    }

    private var calculatedHeight: CGFloat {
        // The two-reading summary and explicit time selector need room on the
        // compact sheet. Historical rows grow only after the primary controls.
        500 + CGFloat(recentEntries.count) * 54
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Drag Indicator spacing + Title
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Log body weight")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(GymTheme.label)

                    Text("Today, \(Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color(white: 0.60))
                }
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(activeAccent)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .padding(.top, 28)

            Picker("Reading time", selection: $selectedSlot) {
                ForEach(BodyweightReadingSlot.allCases) { slot in
                    Text(slot.title).tag(slot)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityHint("Choose whether this is your morning or night weigh-in")

            Text("Log both readings to use their daily average in your progress metrics.")
                .font(.system(size: 13.5))
                .foregroundStyle(GymTheme.label2)
                .fixedSize(horizontal: false, vertical: true)

            if let todayEntry {
                dailySummary(todayEntry)
            }

            WeightInputView(value: $weight, unit: "kg", minVal: 30.0, maxVal: 200.0, isInteger: false)
                .padding(.vertical, 4)

            Button {
                saveWeight()
            } label: {
                Text("Save \(selectedSlot.title) reading")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(activeAccent, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            if let savedSummary {
                Text(savedSummary)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(activeAccent)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

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

                            if item.morningKg != nil || item.nightKg != nil {
                                Text(readingDetail(for: item))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(GymTheme.label3)
                            }

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
            loadSelectedReading()
        }
        .onChange(of: selectedSlot) { _, _ in loadSelectedReading() }
        .presentationDetents([.height(calculatedHeight)])
        .presentationDragIndicator(.visible)
    }

    private func seedEntriesIfEmpty() {
        if entries.isEmpty {
            let cal = Calendar.appWeek
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

        guard let entry = try? BodyweightLogStore.record(weight, for: selectedSlot, in: context) else { return }
        profiles.first?.weightKg = entry.kg
        try? context.save()
        onSaved?(entry.kg)
        savedSummary = "\(selectedSlot.title) saved · daily average \(String(format: "%.1f", entry.kg)) kg"

        let nextSlot: BodyweightReadingSlot = selectedSlot == .morning ? .night : .morning
        if (nextSlot == .morning ? entry.morningKg : entry.nightKg) == nil {
            selectedSlot = nextSlot
            weight = entry.kg
        }
    }

    @ViewBuilder
    private func dailySummary(_ entry: BodyweightEntryModel) -> some View {
        HStack(spacing: 10) {
            summaryValue(title: "AM", value: entry.morningKg)
            Divider().frame(height: 28)
            summaryValue(title: "PM", value: entry.nightKg)
            Divider().frame(height: 28)
            VStack(alignment: .trailing, spacing: 2) {
                Text("DAILY AVG")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(GymTheme.label3)
                Text(String(format: "%.1f kg", entry.kg))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(activeAccent)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func summaryValue(title: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(GymTheme.label3)
            Text(value.map { String(format: "%.1f", $0) } ?? "—")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(value == nil ? GymTheme.label3 : GymTheme.label)
                .monospacedDigit()
        }
        .frame(minWidth: 48, alignment: .leading)
    }

    private func loadSelectedReading() {
        guard let todayEntry else { return }
        weight = (selectedSlot == .morning ? todayEntry.morningKg : todayEntry.nightKg) ?? todayEntry.kg
    }

    private func readingDetail(for entry: BodyweightEntryModel) -> String {
        let readings = [
            entry.morningKg.map { "AM \(String(format: "%.1f", $0))" },
            entry.nightKg.map { "PM \(String(format: "%.1f", $0))" }
        ]
        .compactMap { $0 }

        return readings.joined(separator: " · ")
    }

    private func deleteEntry(_ entry: BodyweightEntryModel) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        context.delete(entry)
        try? context.save()
    }
}
