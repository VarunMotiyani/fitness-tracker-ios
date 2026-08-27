import SwiftUI
import FitnessDomain

struct ExperienceStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        List(ExperienceLevel.allCases, id: \.self) { level in
            Button {
                model.experience = level
            } label: {
                HStack {
                    Text(level.label)
                    Spacer()
                    if model.experience == level {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Your experience")
        .navigationBarTitleDisplayMode(.inline)
    }
}
