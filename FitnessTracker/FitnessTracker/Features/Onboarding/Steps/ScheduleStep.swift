import SwiftUI

struct ScheduleStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        Form {
            Stepper("Sessions per week: \(model.sessionsPerWeek)",
                    value: $model.sessionsPerWeek, in: 2...7)

            Picker("Typical session length", selection: $model.sessionLengthMinutes) {
                Text("30 min").tag(30)
                Text("45 min").tag(45)
                Text("60 min").tag(60)
                Text("90 min").tag(90)
            }

            Section {
                Text("This is a ceiling, not a commitment — the plan adapts to what you actually do.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Your schedule")
        .navigationBarTitleDisplayMode(.inline)
    }
}
