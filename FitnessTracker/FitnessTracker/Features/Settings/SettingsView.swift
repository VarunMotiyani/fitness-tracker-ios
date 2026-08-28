import SwiftUI
import SwiftData
import ExerciseCatalog

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    @Query(sort: \StoredPlan.generatedAt, order: .reverse) private var plans: [StoredPlan]
    @Query(filter: #Predicate<ProviderProfile> { $0.isActive }) private var activeProfiles: [ProviderProfile]

    @State private var catalog: CatalogStore?

    var body: some View {
        Form {
            if let p = profiles.first {
                Section("Profile") {
                    LabeledContent("Goal", value: p.goalRaw)
                    LabeledContent("Experience", value: p.experienceRaw)
                    LabeledContent("Sessions / week", value: "\(p.sessionsPerWeek)")
                    LabeledContent("Session length", value: "\(p.sessionLengthMinutes) min")
                    LabeledContent("Equipment", value: "\(p.availableEquipmentRaws.count) items")
                    if !p.excludedMuscleRaws.isEmpty {
                        LabeledContent("Avoiding", value: "\(p.excludedMuscleRaws.count) area(s)")
                    }
                }
                Section {
                    Button("Regenerate plan") { regenerate(p) }
                }
                Section {
                    Button("Start over", role: .destructive) { startOver() }
                }
            } else {
                Text("No profile yet.")
            }

            Section("AI Coach") {
                LabeledContent("Status", value: "Coming in Phase 1c")
            }
            .disabled(true)
        }
        .navigationTitle("Settings")
        .task {
            if catalog == nil { catalog = try? BundledCatalog.load() }
        }
    }

    private func regenerate(_ profile: UserProfile) {
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

    private func startOver() {
        // Pop back to the root first, then delete — so we don't sit on a
        // Settings screen whose profile no longer exists.
        dismiss()
        let staleProfiles = Array(profiles)
        let stalePlans = Array(plans)
        for plan in stalePlans { context.delete(plan) }
        for profile in staleProfiles { context.delete(profile) }
        try? context.save()
    }
}
