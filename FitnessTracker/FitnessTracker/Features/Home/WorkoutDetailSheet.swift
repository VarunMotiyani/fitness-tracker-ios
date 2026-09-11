import SwiftUI
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics

struct WorkoutDetailSheet: View {
    let session: CompletedSessionModel
    let catalog: CatalogStore
    var onSavedCheckin: ((DailyCheckinModel) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \DailyCheckinModel.date, order: .reverse)
    private var dailyCheckins: [DailyCheckinModel]

    @AppStorage("gym_accent_color") private var accentColorKey: String = "lime"
    private var activeAccent: Color { GymTheme.accent(for: accentColorKey) }

    @State private var showCheckinSheet = false

    private var isToday: Bool {
        Calendar.appWeek.isDate(session.startedAt, inSameDayAs: .now)
    }

    private var dayCheckin: DailyCheckinModel? {
        dailyCheckins.first { Calendar.appWeek.isDate($0.date, inSameDayAs: session.startedAt) }
    }

    private var checkinSummaryText: String {
        guard let checkin = dayCheckin else {
            return "Share sleep and soreness so your coach can adapt."
        }
        var parts: [String] = []
        if let sleep = checkin.sleepQuality {
            parts.append("Sleep: \(sleep)/10")
        }
        if let sore = checkin.soreness {
            parts.append("Soreness: \(sore)/10")
        }
        if let note = checkin.note, !note.isEmpty {
            parts.append(note)
        }
        return parts.isEmpty ? "Sleep and soreness saved" : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var checkinSection: some View {
        if isToday {
            Button {
                showCheckinSheet = true
            } label: {
                checkinCardContent(isEditable: true)
            }
            .buttonStyle(.plain)
        } else if dayCheckin != nil {
            checkinCardContent(isEditable: false)
        }
    }

    @ViewBuilder
    private func checkinCardContent(isEditable: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: dayCheckin == nil ? "heart.text.square.fill" : "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(dayCheckin == nil ? GymTheme.violet : activeAccent)
                .frame(width: 40, height: 40)
                .background((dayCheckin == nil ? GymTheme.violet : activeAccent).opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(dayCheckin == nil ? "How are you feeling?" : (isToday ? "Today’s check-in" : "Daily check-in"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(GymTheme.label)

                Text(checkinSummaryText)
                    .font(.footnote)
                    .foregroundStyle(GymTheme.label2)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if isEditable {
                Text(dayCheckin == nil ? "Check in" : "Update")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(activeAccent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 12))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header Title & Stats
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Session Details")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(GymTheme.label)

                        let dur = session.actualDurationMin
                        let totalKg = session.entries.reduce(0.0) { sum, e in
                            sum + e.sets.reduce(0.0) { sSum, s in sSum + (s.actualLoadKg * Double(s.actualReps)) }
                        }
                        Text("\(session.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(dur)m · \(String(format: "%.1f kg", totalKg))")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color(white: 0.60))
                    }
                    .padding(.top, 8)

                    checkinSection

                    // Completed Exercises List
                    VStack(spacing: 12) {
                        ForEach(session.entries.sorted { $0.performedOrder < $1.performedOrder }, id: \.id) { entry in
                            let ex = catalog.exercise(id: entry.exerciseID)
                            HStack(alignment: .top, spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(white: 0.60))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "dumbbell.fill")
                                        .font(.title3)
                                        .foregroundStyle(GymTheme.green)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(ex?.name ?? entry.exerciseID)
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(GymTheme.label)
                                    }

                                    // Sets breakdown
                                    let setStrings = entry.sets.sorted { $0.startedAt < $1.startedAt }.map { s in
                                        "\(String(format: "%.1f", s.actualLoadKg))×\(s.actualReps)"
                                    }
                                    Text(setStrings.joined(separator: " · "))
                                        .font(.footnote.weight(.regular)).fontDesign(.monospaced)
                                        .foregroundStyle(Color(white: 0.70))
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    // Overall note if present
                    if let note = session.overallNote, !note.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Session note")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(white: 0.60))
                            Text(note)
                                .font(.subheadline)
                                .foregroundStyle(Color(white: 0.80))
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .background(GymTheme.bgElevated.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color(white: 0.5))
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showCheckinSheet) {
            CheckinEntryView { checkin in
                onSavedCheckin?(checkin)
            }
        }
    }
}
