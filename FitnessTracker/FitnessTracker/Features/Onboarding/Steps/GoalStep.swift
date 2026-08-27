import SwiftUI
import FitnessDomain

struct GoalStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        List(Goal.allCases, id: \.self) { goal in
            Button {
                model.goal = goal
            } label: {
                HStack {
                    Text(goal.label)
                    Spacer()
                    if model.goal == goal {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Your main goal")
        .navigationBarTitleDisplayMode(.inline)
    }
}
