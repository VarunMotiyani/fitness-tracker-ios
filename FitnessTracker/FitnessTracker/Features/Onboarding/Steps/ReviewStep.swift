import SwiftUI

struct ReviewStep: View {
    @Bindable var model: OnboardingModel
    let onCreate: () -> Void

    var body: some View {
        Form {
            Section("Summary") {
                LabeledContent("Goal", value: model.goal?.label ?? "—")
                LabeledContent("Experience", value: model.experience?.label ?? "—")
                LabeledContent("Sessions / week", value: "\(model.sessionsPerWeek)")
                LabeledContent("Session length", value: "\(model.sessionLengthMinutes) min")
                LabeledContent("Equipment", value: "\(model.equipment.count) selected")
                if !model.excludedMuscles.isEmpty {
                    LabeledContent("Avoiding", value: "\(model.excludedMuscles.count) area(s)")
                }
            }
            Section {
                Button("Create my plan", action: onCreate)
                    .disabled(!model.isComplete)
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
    }
}
