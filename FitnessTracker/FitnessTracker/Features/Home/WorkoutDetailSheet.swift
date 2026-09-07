import SwiftUI
import FitnessDomain
import ExerciseCatalog

struct WorkoutDetailSheet: View {
    let session: CompletedSessionModel
    let catalog: CatalogStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header Title & Stats
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Session Details")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(GymTheme.label)

                        let dur = session.actualDurationMin
                        let totalKg = session.entries.reduce(0.0) { sum, e in
                            sum + e.sets.reduce(0.0) { sSum, s in sSum + (s.actualLoadKg * Double(s.actualReps)) }
                        }
                        Text("\(session.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(dur)m · \(String(format: "%.1f kg", totalKg))")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(white: 0.60))
                    }
                    .padding(.top, 8)

                    // Completed Exercises List
                    VStack(spacing: 12) {
                        ForEach(session.entries.sorted { $0.performedOrder < $1.performedOrder }, id: \.id) { entry in
                            let ex = catalog.exercise(id: entry.exerciseID)
                            HStack(alignment: .top, spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(white: 0.16))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "dumbbell.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(GymTheme.green)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(ex?.name ?? entry.exerciseID)
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundStyle(GymTheme.label)
                                    }

                                    // Sets breakdown
                                    let setStrings = entry.sets.sorted { $0.startedAt < $1.startedAt }.map { s in
                                        "\(String(format: "%.1f", s.actualLoadKg))×\(s.actualReps)"
                                    }
                                    Text(setStrings.joined(separator: " · "))
                                        .font(.system(size: 13, weight: .regular, design: .monospaced))
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
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(white: 0.50))
                            Text(note)
                                .font(.system(size: 14))
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
    }
}
