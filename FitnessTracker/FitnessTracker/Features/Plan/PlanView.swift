import SwiftUI
import FitnessDomain
import ExerciseCatalog

/// Read-only rendering of a generated weekly plan.
struct PlanView: View {
    let plan: WeeklyPlan
    let catalog: CatalogStore
    let costSummary: CostSummary

    var body: some View {
        List {
            Section {
                Text(plan.rationale)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(orderedSessions) { session in
                Section("Session \(session.order + 1)  ·  \(focusText(session))") {
                    ForEach(Array(session.items.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name(for: item.exerciseID))
                                .font(.headline)
                            Text("\(item.targetSets) × \(item.targetReps.min)–\(item.targetReps.max)  ·  rest \(item.restSeconds)s")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(item.coachNote)
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section("Weekly volume targets") {
                ForEach(plan.weeklyVolumeTargets, id: \.muscle) { target in
                    LabeledContent(target.muscle.label, value: "\(target.targetSets) sets")
                }
            }
        }
        .navigationTitle("This week")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                CostChip(summary: costSummary)
            }
        }
    }

    private var orderedSessions: [PlannedSession] {
        plan.sessions.sorted { $0.order < $1.order }
    }

    private func name(for id: String) -> String {
        catalog.exercise(id: id)?.name ?? id
    }

    private func focusText(_ session: PlannedSession) -> String {
        session.focusMuscles.map(\.label).joined(separator: ", ")
    }
}
