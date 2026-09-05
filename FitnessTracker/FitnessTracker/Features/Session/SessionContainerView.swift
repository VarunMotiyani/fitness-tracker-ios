import SwiftUI
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics
import LLMKit

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
    // Plain @Query + Swift-side filter, not a #Predicate on `isActive` — a
    // #Predicate<ProviderProfile> boolean filter thrashing CoreData's SQL
    // generator is exactly what hung Settings/Providers earlier this project.
    @Query private var allProviderProfiles: [ProviderProfile]
    @Query private var allMemories: [CoachMemoryModel]
    private var activeProviderProfile: ProviderProfile? { allProviderProfiles.first { $0.isActive } }

    /// Optional because `SessionRunner` needs `modelContext`, which isn't
    /// available at `init`. Built once in `.task`.
    @State private var runner: SessionRunner?
    @State private var showList = false

    var body: some View {
        content
            .task {
                if runner == nil {
                    let cat = catalog
                    let plannedID = planned.id

                    // F7: close any earlier in-progress session for this planned
                    // slot so re-entering doesn't leave an orphan `finishedAt ==
                    // nil` row. Everything logged in it keeps its volume/PR
                    // credit (F1 promotion runs inside the helper).
                    let orphans = ((try? context.fetch(FetchDescriptor<CompletedSessionModel>())) ?? [])
                        .filter { $0.finishedAt == nil && $0.plannedSessionID == plannedID }
                    for orphan in orphans {
                        SessionRunner.closeSessionAsPartial(orphan, in: context, now: Date())
                    }

                    let repo = SwiftDataMetricsRepository(
                        context: context,
                        catalog: cat,
                        plannedSessionsPerWeek: profiles.first?.sessionsPerWeek ?? 3
                    )
                    let ruleEngineFallback = RuleEngineFinalizer(catalog: cat, repository: repo)

                    var provider: (any LLMProvider)?
                    if let activeProviderProfile {
                        provider = try? LLMProviderFactory.make(from: activeProviderProfile)
                    }
                    let fin: any SessionFinalizing = SessionFinalizeCoordinator(
                        catalog: cat, context: context, provider: provider,
                        activeProfile: activeProviderProfile,
                        memories: allMemories.map { $0.toDomain() },
                        ruleEngineFallback: ruleEngineFallback
                    )
                    let keeper: (any MemoryKeeperRunning)? = provider.map {
                        MemoryKeeperCoordinator(catalog: cat, context: context, provider: $0,
                                                activeProfile: activeProviderProfile)
                    }
                    runner = SessionRunner(modelContext: context, catalog: cat,
                                           repository: repo, finalizer: fin, memoryKeeper: keeper)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch runner?.phase {
        case .none:
            // Runner not built yet (`.task` hasn't run). Don't show Start —
            // a tap here would be a silent no-op against a nil runner.
            ProgressView("Preparing…")
        case .idle:
            SessionStartView(planned: planned, catalog: catalog) { energy, minutes in
                Task { await runner?.start(planned: planned, energy: energy, timeAvailableMin: minutes) }
            }
        case .finalizing:
            ProgressView("Building today's session…")
        case .active:
            if let runner {
                NavigationStack {
                    SessionFocusView(runner: runner, catalog: catalog) {
                        showList = true
                    }
                }
                .sheet(isPresented: $showList) {
                    SessionListView(runner: runner, catalog: catalog) {
                        runner.requestSummary()
                    }
                    .presentationDetents([.large])
                }
                .onChange(of: runner.phase) { _, _ in showList = false }   // F5: belt-and-braces
            }
        case .summary:
            if let runner {
                SessionSummaryView(runner: runner, catalog: catalog) { runner.closeSummary() }
            }
        case .finished:
            Color.clear.onAppear { onFinished() }
        }
    }
}
