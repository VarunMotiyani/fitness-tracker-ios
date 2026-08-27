import SwiftUI
import FitnessDomain

struct LimitationsStep: View {
    @Bindable var model: OnboardingModel

    /// The areas onboarding can currently exclude. Selecting one makes the plan
    /// skip training that muscle group entirely (1b only has whole-muscle
    /// exclusion; per-exercise "won't do" arrives with the injury feature).
    private let areas: [MuscleGroup] = [.lowerBack, .shoulders, .hamstrings, .biceps]

    var body: some View {
        List {
            Section {
                Text("Optional — skip if nothing's bothering you.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Skip training these areas") {
                ForEach(areas, id: \.self) { area in
                    Button {
                        if model.excludedMuscles.contains(area) {
                            model.excludedMuscles.remove(area)
                        } else {
                            model.excludedMuscles.insert(area)
                        }
                    } label: {
                        HStack {
                            Text(area.label)
                            Spacer()
                            if model.excludedMuscles.contains(area) {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Anything to avoid?")
        .navigationBarTitleDisplayMode(.inline)
    }
}
