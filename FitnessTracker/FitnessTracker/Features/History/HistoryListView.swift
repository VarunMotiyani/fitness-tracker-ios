import SwiftUI
import SwiftData
import FitnessDomain
import ExerciseCatalog

struct HistoryListView: View {
    let catalog: CatalogStore

    @Query(sort: \CompletedSessionModel.startedAt, order: .reverse)
    private var sessions: [CompletedSessionModel]

    init(catalog: CatalogStore) {
        self.catalog = catalog
    }

    public var body: some View {
        List {
            if sessions.isEmpty {
                ContentUnavailableView("No Workouts Yet", systemImage: "clock.arrow.circlepath", description: Text("Completed sessions will appear here with tonnage, PRs, and exercise breakdowns."))
            } else {
                ForEach(sessions.filter { $0.finishedAt != nil }) { session in
                    NavigationLink {
                        sessionDetail(session)
                    } label: {
                        sessionRow(session)
                    }
                    .listRowBackground(Color(white: 0.12))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Workout History")
    }

    @ViewBuilder
    private func sessionRow(_ session: CompletedSessionModel) -> some View {
        let totalVolume = session.entries.reduce(0.0) { sum, e in
            sum + e.sets.reduce(0.0) { setSum, s in
                s.isWarmup ? setSum : setSum + (s.actualLoadKg * Double(s.actualReps))
            }
        }
        let totalSets = session.entries.reduce(0) { $0 + $1.sets.filter { !$0.isWarmup }.count }

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.startedAt.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                if let finishedAt = session.finishedAt {
                    let durationMin = max(1, Int(finishedAt.timeIntervalSince(session.startedAt) / 60))
                    Text("\(durationMin) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Label("\(totalSets) sets", systemImage: "number")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(String(format: "%.0f kg volume", totalVolume), systemImage: "scalemass.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Exercise names preview
            Text(session.entries.map { catalog.exercise(id: $0.exerciseID)?.name ?? $0.exerciseID }.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func sessionDetail(_ session: CompletedSessionModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.startedAt.formatted(.dateTime.weekday(.wide).month().day().year()))
                        .font(.title3.bold())
                    if let note = session.overallNote, !note.isEmpty {
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                ForEach(session.entries, id: \.persistentModelID) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(catalog.exercise(id: entry.exerciseID)?.name ?? entry.exerciseID)
                            .font(.headline)

                        ForEach(Array(entry.sets.enumerated()), id: \.offset) { idx, set in
                            HStack {
                                Text("Set \(idx + 1)")
                                    .font(.caption.bold())
                                    .foregroundStyle(set.isWarmup ? .orange : .secondary)
                                if set.isWarmup {
                                    Text("WARMUP")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 4)
                                        .background(Color.orange.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                                        .foregroundStyle(.orange)
                                }
                                Spacer()
                                Text(String(format: "%.1f kg × %d reps", set.actualLoadKg, set.actualReps))
                                    .font(.subheadline.monospacedDigit())
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding()
                    .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Session Summary")
    }
}
