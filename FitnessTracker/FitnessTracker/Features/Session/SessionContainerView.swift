import SwiftUI
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics

/// Phase router for the session runner. Owns the `SessionRunner` (built lazily
/// in `.task`, since it needs the `modelContext`) and swaps in the screen for
/// the current `runner.phase`. `onFinished` is called once the runner reaches
/// `.finished` (Task 12's caller passes a dismiss).
struct SessionContainerView: View {
    let planned: PlannedSession
    let catalog: CatalogStore
    let onFinished: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    /// Optional because `SessionRunner` needs `modelContext`, which isn't
    /// available at `init`. Built once in `.task`.
    @State private var runner: SessionRunner?

    var body: some View {
        content
            .task {
                if runner == nil {
                    let cat = catalog
                    let repo = SwiftDataMetricsRepository(
                        context: context,
                        catalog: cat,
                        plannedSessionsPerWeek: profiles.first?.sessionsPerWeek ?? 3
                    )
                    let fin = SessionFinalizer(catalog: cat, repository: repo)
                    runner = SessionRunner(modelContext: context, catalog: cat,
                                           repository: repo, finalizer: fin)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch runner?.phase {
        case .none, .idle:
            SessionStartView(planned: planned, catalog: catalog) { energy, minutes in
                runner?.start(planned: planned, energy: energy, timeAvailableMin: minutes)
            }
        case .finalizing:
            ProgressView("Building today's session…")
        case .active:
            // TODO(task8/9): SessionFocusView + SessionListView pull-tab.
            Text("Session in progress — Focus view lands in Task 8")
                .foregroundStyle(.secondary)
        case .summary:
            // TODO(task11): SessionSummaryView.
            VStack(spacing: 16) {
                Text("Summary — Task 11")
                    .foregroundStyle(.secondary)
                Button("Done") { runner?.closeSummary() }
                    .buttonStyle(.borderedProminent)
            }
        case .finished:
            Color.clear.onAppear { onFinished() }
        }
    }
}
