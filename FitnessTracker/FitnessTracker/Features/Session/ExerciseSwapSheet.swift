import SwiftUI
import FitnessDomain
import ExerciseCatalog
import RuleEngine

struct ExerciseSwapSheet: View {
    @Environment(\.dismiss) private var dismiss
    let currentExercise: Exercise
    let catalog: CatalogStore
    let onSwap: (Exercise, Bool, ActiveWorkoutEdits.GroupDisposition?) -> Void

    @State private var searchQuery: String = ""
    @State private var selectedMuscle: MuscleGroup?
    @State private var selectedExercise: Exercise?
    @State private var showConfirmLogged: Bool = false

    @AppStorage("gym_equip_filter_on") private var equipFilterOn: Bool = false
    @AppStorage("gym_active_profile_id") private var activeProfileID: String = "commercial_gym"
    @AppStorage("gym_equipment_profiles_json") private var profilesJSON: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Current exercise banner
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title2)
                        .foregroundStyle(GymTheme.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Swapping from")
                            .font(.caption)
                            .foregroundStyle(GymTheme.label3)
                        Text(currentExercise.name)
                            .font(.headline)
                            .foregroundStyle(GymTheme.label)
                    }
                    Spacer()
                }
                .padding()
                .background(GymTheme.surface2)

                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(GymTheme.label3)
                    TextField("Search replacement...", text: $searchQuery)
                        .textFieldStyle(.plain)
                    if !searchQuery.isEmpty {
                        Button { searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(GymTheme.label3)
                        }
                    }
                }
                .padding(10)
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Muscle Filter Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(title: "Same Muscle (\(currentExercise.primaryMuscle.rawValue.capitalized))", isSelected: selectedMuscle == currentExercise.primaryMuscle) {
                            selectedMuscle = currentExercise.primaryMuscle
                        }
                        filterChip(title: "All", isSelected: selectedMuscle == nil) {
                            selectedMuscle = nil
                        }
                        ForEach(MuscleGroup.allCases, id: \.self) { m in
                            if m != currentExercise.primaryMuscle {
                                filterChip(title: m.rawValue.capitalized, isSelected: selectedMuscle == m) {
                                    selectedMuscle = m
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 8)

                // Results list
                List(filteredExercises, id: \.id) { ex in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ex.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(GymTheme.label)
                            HStack(spacing: 6) {
                                Text(ex.primaryMuscle.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(GymTheme.green)
                                Text("·")
                                    .foregroundStyle(GymTheme.label3)
                                Text(ex.equipment.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(GymTheme.label2)
                            }
                        }
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                            .foregroundStyle(GymTheme.green)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedExercise = ex
                        onSwap(ex, true, .keep)
                        dismiss()
                    }
                }
                .listStyle(.plain)
            }
            .background(GymTheme.bg.ignoresSafeArea())
            .navigationTitle("Swap Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(GymTheme.label2)
                }
            }
            .onAppear {
                selectedMuscle = currentExercise.primaryMuscle
            }
        }
    }

    private var filteredExercises: [Exercise] {
        var pool = catalog.all.filter { $0.id != currentExercise.id }
        pool = pool.filter {
            EquipmentFilter.isAvailable(
                $0,
                filterOn: equipFilterOn,
                activeID: activeProfileID,
                profilesJSON: profilesJSON
            )
        }
        if let m = selectedMuscle {
            pool = pool.filter { $0.primaryMuscle == m }
        }
        if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            let q = searchQuery.lowercased()
            pool = pool.filter { $0.name.lowercased().contains(q) }
        }
        return pool
    }

    @ViewBuilder
    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? GymTheme.green : GymTheme.surface2, in: Capsule())
                .foregroundStyle(isSelected ? .black : GymTheme.label)
        }
        .buttonStyle(.plain)
    }
}
