import SwiftUI
import SwiftData
import Metrics

/// A small form sheet for logging today's subjective check-in: sleep quality and
/// soreness on 1–10 scales plus an optional note. On Save it upserts today's
/// `DailyCheckinModel`, persists, and hands the row to `onSaved` (which the Home
/// entry point uses to fire `ProactiveCoordinator.reactToCheckin`).
struct CheckinEntryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var allCheckins: [DailyCheckinModel]

    @AppStorage("gym_accent_color") private var accentColorKey: String = "lime"
    private var activeAccent: Color { GymTheme.accent(for: accentColorKey) }

    @State private var sleepQuality: Double = 7
    @State private var soreness: Double = 3
    @State private var note: String = ""
    @State private var saveError: String?

    /// Called with the persisted row after Save, before dismiss.
    var onSaved: (DailyCheckinModel) -> Void

    init(onSaved: @escaping (DailyCheckinModel) -> Void) {
        self.onSaved = onSaved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Title
            VStack(alignment: .leading, spacing: 4) {
                Text("Daily check-in")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(GymTheme.label)

                Text("Today, \(Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color(white: 0.60))
            }
            .padding(.top, 28)

            ratingRow(title: "Sleep quality", value: $sleepQuality)
            ratingRow(title: "Soreness", value: $soreness)

            // Note field
            VStack(alignment: .leading, spacing: 6) {
                Text("Note")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(white: 0.50))

                TextField("Anything worth telling your coach", text: $note, axis: .vertical)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(GymTheme.label)
                    .lineLimit(1...3)
                    .padding(12)
                    .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 12))
            }

            // Save Button
            Button {
                save()
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
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .background(GymTheme.bgElevated.ignoresSafeArea())
        .presentationDetents([.height(430)])
        .presentationDragIndicator(.visible)
        .onAppear(perform: prefillFromToday)
        .alert("Couldn't save check-in", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    /// Seed the sliders + note from today's existing check-in so reopening the
    /// sheet and hitting Save doesn't clobber real values with the 7/3 defaults.
    private func prefillFromToday() {
        guard let today = allCheckins.first(where: { Calendar.appWeek.isDate($0.date, inSameDayAs: .now) })
        else { return }
        if let s = today.sleepQuality { sleepQuality = Double(s) }
        if let so = today.soreness { soreness = Double(so) }
        note = today.note ?? ""
    }

    @ViewBuilder
    private func ratingRow(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(white: 0.50))

                Spacer()

                Text("\(Int(value.wrappedValue.rounded()))")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(activeAccent)
            }

            Slider(value: value, in: 1...10, step: 1)
                .tint(activeAccent)
        }
    }

    private func save() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        let checkin = allCheckins.first { Calendar.appWeek.isDate($0.date, inSameDayAs: .now) }
            ?? {
                let fresh = DailyCheckinModel(date: .now)
                context.insert(fresh)
                return fresh
            }()

        checkin.sleepQuality = Int(sleepQuality.rounded())
        checkin.soreness = Int(soreness.rounded())
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        checkin.note = trimmed.isEmpty ? nil : trimmed

        do {
            try context.save()
            onSaved(checkin)
            dismiss()
        } catch {
            saveError = "Could not save check-in: \(error.localizedDescription)"
        }
    }
}
