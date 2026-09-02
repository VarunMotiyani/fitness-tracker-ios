import SwiftUI
import SwiftData
import FitnessDomain

struct EquipmentProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let profile: UserProfile

    @State private var selectedEquipment: Set<Equipment> = []

    init(profile: UserProfile) {
        self.profile = profile
        let existing = Set(profile.availableEquipmentRaws.compactMap { Equipment(rawValue: $0) })
        self._selectedEquipment = State(initialValue: existing.isEmpty ? Set(Equipment.allCases) : existing)
    }

    var body: some View {
        NavigationStack {
            List(Equipment.allCases, id: \.self) { item in
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    if selectedEquipment.contains(item) {
                        if selectedEquipment.count > 1 { // keep at least 1
                            selectedEquipment.remove(item)
                        }
                    } else {
                        selectedEquipment.insert(item)
                    }
                    save()
                } label: {
                    HStack {
                        Text(item.label)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(GymTheme.label)
                        Spacer()
                        if selectedEquipment.contains(item) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(GymTheme.green)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Equipment Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(GymTheme.green)
                }
            }
        }
    }

    private func save() {
        profile.availableEquipmentRaws = selectedEquipment.map(\.rawValue)
        try? context.save()
    }
}
