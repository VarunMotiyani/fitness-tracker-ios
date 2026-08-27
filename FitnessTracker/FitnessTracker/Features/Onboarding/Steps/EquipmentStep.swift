import SwiftUI
import FitnessDomain

struct EquipmentStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        List(Equipment.allCases, id: \.self) { item in
            Button {
                if model.equipment.contains(item) {
                    model.equipment.remove(item)
                } else {
                    model.equipment.insert(item)
                }
            } label: {
                HStack {
                    Text(item.label)
                    Spacer()
                    if model.equipment.contains(item) {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("What can you use?")
        .navigationBarTitleDisplayMode(.inline)
    }
}
