//
//  RootView.swift
//  FitnessTracker
//
//  Created by Motiyani, Varun on 28/08/26.
//

import SwiftUI
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(sort: \StoredPlan.generatedAt, order: .reverse) private var plans: [StoredPlan]
    @Query private var allProviderProfiles: [ProviderProfile]
    private var activeProfiles: [ProviderProfile] { allProviderProfiles.filter(\.isActive) }
    @Query(sort: \AICallRecord.timestamp) private var calls: [AICallRecord]

    @State private var catalog: CatalogStore?
    @State private var loadFailed = false
    @State private var lastNote: String?
    @State private var isGenerating = false

    // openGym 5-tab navigation state
    @State private var selectedTab: AppTab = .home
    @State private var activePlannedSession: PlannedSession?
    @State private var showSettings = false

    private var summary: CostSummary {
        CostSummary.from(records: calls.map { .init(timestamp: $0.timestamp, costUSD: $0.costUSD) },
                         now: .now)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // openGym Custom Bottom Navigation Bar
            if profiles.first != nil, let plan = try? plans.first?.decodedPlan() {
                CustomTabBar(
                    selectedTab: $selectedTab,
                    isWorkoutActive: activePlannedSession != nil,
                    onStartPressed: {
                        if let firstSession = plan.sessions.sorted(by: { $0.order < $1.order }).first {
                            activePlannedSession = firstSession
                        }
                    }
                )
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $activePlannedSession) { session in
            if let catalog {
                SessionContainerView(planned: session, catalog: catalog) {
                    activePlannedSession = nil
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
            }
        }
        .overlay(alignment: .top) {
            if let lastNote {
                Text(lastNote)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .center) {
            if isGenerating {
                ProgressView("Updating your plan…")
                    .padding()
                    .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 12))
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
            if profiles.isEmpty, let catalog {
                let defaultProfile = UserProfile(
                    goalRaw: "buildMuscle",
                    experienceRaw: "intermediate",
                    heightCm: 178,
                    weightKg: 75,
                    birthYear: 2000,
                    sexRaw: "male",
                    sessionsPerWeek: 4,
                    sessionLengthMinutes: 60,
                    availableEquipmentRaws: ["barbell", "dumbbell", "cable", "machine", "bodyweight"],
                    excludedMuscleRaws: [],
                    excludedExerciseIDs: []
                )
                context.insert(defaultProfile)
                regeneratePlan(for: defaultProfile)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loadFailed {
            ContentUnavailableView("Couldn't load the exercise catalog",
                                   systemImage: "exclamationmark.triangle")
        } else if let profile = profiles.first, let plan = try? plans.first?.decodedPlan(), let catalog {
            Group {
                switch selectedTab {
                case .home:
                    HomeView(
                        profile: profile,
                        plan: plan,
                        catalog: catalog,
                        costSummary: summary,
                        onStartSession: { session in activePlannedSession = session },
                        onOpenSettings: { showSettings = true }
                    )
                case .plan:
                    PlanView(
                        plan: plan,
                        catalog: catalog,
                        onStartSession: { session in activePlannedSession = session }
                    )
                case .start:
                    WorkoutTabView(
                        plan: plan,
                        catalog: catalog,
                        onStartSession: { session in activePlannedSession = session }
                    )
                case .stats:
                    StatsView(
                        plan: plan,
                        catalog: catalog
                    )
                case .exercises:
                    LibraryView(
                        catalog: catalog
                    )
                }
            }
        } else if profiles.isEmpty {
            OnboardingView { profile in
                context.insert(profile)
                regeneratePlan(for: profile)
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
