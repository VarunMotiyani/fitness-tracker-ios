import SwiftUI
import FitnessDomain

struct EquipmentProfileSheet: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("gym_equip_filter_on") private var equipFilterOn: Bool = false
    @AppStorage("gym_active_profile_id") private var activeProfileID: String = "commercial_gym"
    @AppStorage("gym_equipment_profiles_json") private var profilesJSON: String = ""

    @State private var profiles: [EquipmentProfile] = []
    @State private var editingProfile: EquipmentProfile?
    @State private var showNewSheet: Bool = false
    @State private var newProfileName: String = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Filter by equipment", isOn: $equipFilterOn)
                        .tint(GymTheme.green)
                } footer: {
                    Text("Filters the exercise library and picker to exercises you can perform with your active equipment profile.")
                }

                Section("Profiles") {
                    ForEach(profiles) { profile in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(profile.name)
                                        .font(.headline)
                                        .foregroundStyle(GymTheme.label)
                                    if profile.id == activeProfileID {
                                        Text("ACTIVE")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.black)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(GymTheme.green, in: Capsule())
                                    }
                                }
                                Text("\(profile.availableEquipmentRaws.count) equipment types")
                                    .font(.caption)
                                    .foregroundStyle(GymTheme.label3)
                            }

                            Spacer()

                            Button {
                                editingProfile = profile
                            } label: {
                                Image(systemName: "pencil")
                                    .foregroundStyle(GymTheme.label2)
                            }
                            .buttonStyle(.plain)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            activeProfileID = profile.id
                        }
                    }
                    .onDelete(perform: deleteProfile)

                    Button {
                        newProfileName = ""
                        showNewSheet = true
                    } label: {
                        Label("Add equipment profile", systemImage: "plus")
                            .foregroundStyle(GymTheme.green)
                    }
                }
            }
            .navigationTitle("Equipment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(GymTheme.green)
                }
            }
            .onAppear(perform: loadProfiles)
            .sheet(item: $editingProfile) { prof in
                EditEquipmentProfileSheet(profile: prof) { updated in
                    if let idx = profiles.firstIndex(where: { $0.id == updated.id }) {
                        profiles[idx] = updated
                        saveProfiles()
                    }
                }
            }
            .alert("New Profile", isPresented: $showNewSheet) {
                TextField("Profile Name (e.g. Home Gym)", text: $newProfileName)
                Button("Create") {
                    let newP = EquipmentProfile(
                        name: newProfileName.isEmpty ? "Custom Gym" : newProfileName,
                        availableEquipmentRaws: Equipment.allCases.map(\.rawValue)
                    )
                    profiles.append(newP)
                    activeProfileID = newP.id
                    saveProfiles()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func loadProfiles() {
        if let data = profilesJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([EquipmentProfile].self, from: data),
           !decoded.isEmpty {
            self.profiles = decoded
        } else {
            self.profiles = EquipmentProfile.defaults
            saveProfiles()
        }
    }

    private func saveProfiles() {
        if let encoded = try? JSONEncoder().encode(profiles),
           let str = String(data: encoded, encoding: .utf8) {
            profilesJSON = str
        }
    }

    private func deleteProfile(at offsets: IndexSet) {
        profiles.remove(atOffsets: offsets)
        if !profiles.contains(where: { $0.id == activeProfileID }), let first = profiles.first {
            activeProfileID = first.id
        }
        saveProfiles()
    }
}

struct EditEquipmentProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var profile: EquipmentProfile
    let onSave: (EquipmentProfile) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile Name") {
                    TextField("Name", text: $profile.name)
                }

                Section("Available Equipment") {
                    ForEach(Equipment.allCases, id: \.self) { eq in
                        let isSelected = profile.availableEquipmentRaws.contains(eq.rawValue)
                        HStack {
                            Text(eq.rawValue.capitalized)
                                .foregroundStyle(GymTheme.label)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(GymTheme.green)
                                    .fontWeight(.bold)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isSelected {
                                profile.availableEquipmentRaws.removeAll { $0 == eq.rawValue }
                            } else {
                                profile.availableEquipmentRaws.append(eq.rawValue)
                            }
                        }
                    }
                }
            }
            .navigationTitle(profile.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(profile)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(GymTheme.green)
                }
            }
        }
    }
}
