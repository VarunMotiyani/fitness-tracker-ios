import SwiftUI

struct BodyStep: View {
    @Bindable var model: OnboardingModel

    private let years = Array((1950...2010).reversed())

    var body: some View {
        Form {
            LabeledContent("Height (cm)") {
                TextField("178", value: $model.heightCm, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Weight (kg)") {
                TextField("75", value: $model.weightKg, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            Picker("Birth year", selection: $model.birthYear) {
                Text("—").tag(0)
                ForEach(years, id: \.self) { Text(String($0)).tag($0) }
            }
            Picker("Sex", selection: $model.sex) {
                Text("Male").tag("male")
                Text("Female").tag("female")
                Text("Prefer not to say").tag("unspecified")
            }
        }
        .navigationTitle("About you")
        .navigationBarTitleDisplayMode(.inline)
    }
}
