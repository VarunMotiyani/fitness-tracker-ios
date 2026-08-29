//
//  RootView.swift
//  FitnessTracker
//
//  Created by Motiyani, Varun on 28/08/26.
//

import SwiftUI
import SwiftData
import ExerciseCatalog

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(sort: \StoredPlan.generatedAt, order: .reverse) private var plans: [StoredPlan]
    // `== true` (not a bare `$0.isActive`): SwiftData can fail to lower a
    // bare-Bool #Predicate to a fetch and spin the main thread during a
    // view update.
    @Query(filter: #Predicate<ProviderProfile> { $0.isActive == true }) private var activeProfiles: [ProviderProfile]
    @Query(sort: \AICallRecord.timestamp) private var calls: [AICallRecord]

    @State private var catalog: CatalogStore?
    @State private var loadFailed = false
    @State private var lastNote: String?
    @State private var isGenerating = false

    private var summary: CostSummary {
        CostSummary.from(records: calls.map { .init(timestamp: $0.timestamp, costUSD: $0.costUSD) },
                         now: .now)
    }

    var body: some View {
        NavigationStack {
            content
        }
        .overlay(alignment: .top) {
            if let lastNote {
                Text(lastNote)
                    .padding(8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .center) {
            if isGenerating {
                ProgressView("Updating your plan…")
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .animation(.default, value: lastNote)
        .animation(.default, value: isGenerating)
        .task(id: lastNote) {
            guard lastNote != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            lastNote = nil
        }
        .task {
            SessionRunner.resolveAbandoned(in: context, now: .now)
            if catalog == nil {
                do { catalog = try BundledCatalog.load() }
                catch { loadFailed = true }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loadFailed {
            ContentUnavailableView("Couldn't load the exercise catalog",
                                   systemImage: "exclamationmark.triangle")
        } else if profiles.isEmpty {
            OnboardingView { profile in
                context.insert(profile)
                regeneratePlan(for: profile)
            }
        } else if let plan = try? plans.first?.decodedPlan(), let catalog {
            PlanView(plan: plan, catalog: catalog, costSummary: summary)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink { SettingsView() } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
        } else if let profile = profiles.first {
            ContentUnavailableView {
                Label("No plan yet", systemImage: "dumbbell")
            } actions: {
                Button("Generate plan") { regeneratePlan(for: profile) }
                    .disabled(isGenerating)
                NavigationLink("Settings") { SettingsView() }
            }
        } else {
            ProgressView()
        }
    }

    private func regeneratePlan(for profile: UserProfile) {
        guard let catalog, !isGenerating else { return }
        let userContext = profile.makeUserContext()
        let activeProfile = activeProfiles.first
        isGenerating = true
        Task {
            defer { isGenerating = false }
            let outcome = await generateAndStore(context: userContext,
                                                 activeProfile: activeProfile,
                                                 catalog: catalog,
                                                 modelContext: context)
            lastNote = outcome.note
        }
    }
}
