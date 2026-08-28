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
    @Query(filter: #Predicate<ProviderProfile> { $0.isActive }) private var activeProfiles: [ProviderProfile]

    @State private var catalog: CatalogStore?
    @State private var loadFailed = false

    var body: some View {
        NavigationStack {
            content
        }
        .task {
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
            PlanView(plan: plan, catalog: catalog)
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
                NavigationLink("Settings") { SettingsView() }
            }
        } else {
            ProgressView()
        }
    }

    private func regeneratePlan(for profile: UserProfile) {
        guard let catalog else { return }
        let userContext = profile.makeUserContext()
        let activeProfile = activeProfiles.first
        Task {
            await generateAndStore(context: userContext,
                                   activeProfile: activeProfile,
                                   catalog: catalog,
                                   modelContext: context)
        }
    }
}
