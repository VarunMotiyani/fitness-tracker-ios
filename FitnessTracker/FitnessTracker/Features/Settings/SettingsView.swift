import SwiftUI
import SwiftData
import ExerciseCatalog

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(sort: \StoredPlan.generatedAt, order: .reverse) private var plans: [StoredPlan]

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
        let result = PlanService(catalog: catalog)
            .generate(context: profile.makeUserContext(), weekStartDate: .now)
        if let stored = try? StoredPlan(plan: result.plan,
                                       hadValidationIssues: !result.issues.isEmpty) {
            context.insert(stored)
            try? context.save()
        }
    }

    private func startOver() {
        for plan in plans { context.delete(plan) }
        for profile in profiles { context.delete(profile) }
        try? context.save()
    }
}
