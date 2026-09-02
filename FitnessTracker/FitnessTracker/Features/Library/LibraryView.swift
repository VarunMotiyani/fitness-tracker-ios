import SwiftUI
import FitnessDomain
import ExerciseCatalog

struct LibraryView: View {
    let catalog: CatalogStore

    @State private var searchText = ""
    @State private var selectedMuscle: MuscleGroup? = nil
    @State private var selectedEquipment: Equipment? = nil
    @State private var selectedExerciseForDetail: Exercise? = nil

    private var filteredExercises: [Exercise] {
        catalog.all.filter { ex in
            let matchesSearch = searchText.isEmpty || ex.name.localizedCaseInsensitiveContains(searchText)
            let matchesMuscle = selectedMuscle == nil || ex.primaryMuscle == selectedMuscle! || ex.secondaryMuscles.contains(selectedMuscle!)
            let matchesEquipment = selectedEquipment == nil || ex.equipment == selectedEquipment!
            return matchesSearch && matchesMuscle && matchesEquipment
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                VStack(alignment: .leading, spacing: 3) {
                    Text("Exercises")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(GymTheme.label)
                    Text("\(catalog.all.count) exercises in catalog")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(GymTheme.label2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Search Bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundStyle(GymTheme.label3)
                    TextField("Search exercises...", text: $searchText)
                        .font(.system(size: 15))
                        .foregroundStyle(GymTheme.label)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(GymTheme.label3)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)

                // Muscle Filter Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterPill(title: "All", isSelected: selectedMuscle == nil) {
                            selectedMuscle = nil
                        }
                        ForEach(MuscleGroup.allCases, id: \.self) { muscle in
                            filterPill(title: muscle.label, isSelected: selectedMuscle == muscle) {
                                selectedMuscle = selectedMuscle == muscle ? nil : muscle
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Equipment Filter Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterPill(title: "Any equipment", isSelected: selectedEquipment == nil) {
                            selectedEquipment = nil
                        }
                        ForEach(Equipment.allCases, id: \.self) { eq in
                            filterPill(title: eq.label, isSelected: selectedEquipment == eq) {
                                selectedEquipment = selectedEquipment == eq ? nil : eq
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Exercise List
                LazyVStack(spacing: 8) {
                    ForEach(filteredExercises.prefix(60), id: \.id) { ex in
                        exerciseRow(ex)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 80)
        }
        .background(GymTheme.bg.ignoresSafeArea())
        .sheet(item: $selectedExerciseForDetail) { ex in
            ExerciseDetailSheet(exercise: ex)
        }
    }

    @ViewBuilder
    private func filterPill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    isSelected ? GymTheme.green : GymTheme.surface2,
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? .black : GymTheme.label2)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func exerciseRow(_ ex: Exercise) -> some View {
        Button {
            selectedExerciseForDetail = ex
        } label: {
            HStack(spacing: 12) {
                // Exercise Thumbnail Image
                ExerciseThumbnailView(urlString: ex.imagePaths.first, size: 52, cornerRadius: 8)

                VStack(alignment: .leading, spacing: 3) {
                    Text(ex.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(GymTheme.label)
                        .multilineTextAlignment(.leading)
                    Text("\(ex.primaryMuscle.label) · \(ex.equipment.label)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(GymTheme.label2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(white: 0.35))
            }
            .padding(12)
            .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
