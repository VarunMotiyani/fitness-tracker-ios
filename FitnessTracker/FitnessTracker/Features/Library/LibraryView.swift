import SwiftUI
import FitnessDomain
import ExerciseCatalog

struct LibraryView: View {
    let catalog: CatalogStore

    @State private var searchText = ""
    @State private var selectedMuscle: MuscleGroup? = nil
    @State private var selectedEquipment: Equipment? = nil
    @State private var selectedExerciseForDetail: Exercise? = nil
    @State private var shownCount: Int = 40

    /// Exercises matching search + muscle only — the pool the equipment chips describe.
    private var searchAndMuscleMatches: [Exercise] {
        catalog.all.filter { ex in
            let matchesSearch = searchText.isEmpty || ex.name.localizedCaseInsensitiveContains(searchText)
            let matchesMuscle = selectedMuscle == nil || ex.primaryMuscle == selectedMuscle! || ex.secondaryMuscles.contains(selectedMuscle!)
            return matchesSearch && matchesMuscle
        }
    }

    private var filteredExercises: [Exercise] {
        searchAndMuscleMatches.filter { selectedEquipment == nil || $0.equipment == selectedEquipment! }
    }

    /// Equipment values actually present in the current search/muscle pool, most common
    /// first — so every chip on screen has results behind it.
    private var availableEquipment: [Equipment] {
        var counts: [Equipment: Int] = [:]
        for ex in searchAndMuscleMatches { counts[ex.equipment, default: 0] += 1 }
        return counts.keys.sorted { lhs, rhs in
            let (cl, cr) = (counts[lhs] ?? 0, counts[rhs] ?? 0)
            return cl != cr ? cl > cr : lhs.label < rhs.label
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header (Exercises | 1324 exercises with animations)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Exercises")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(GymTheme.label)
                    Text("\(catalog.all.count) exercises with photos & instructions")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color(white: 0.60))
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // Search Bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundStyle(GymTheme.label3)
                    TextField("Search...", text: $searchText)
                        .font(.system(size: 15))
                        .foregroundStyle(GymTheme.label)
                        .onChange(of: searchText) { _, _ in
                            shownCount = 40
                        }
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            shownCount = 40
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(GymTheme.label3)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)

                // Body Part / Muscle Filter Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(title: "All", isSelected: selectedMuscle == nil) {
                            selectedMuscle = nil
                            shownCount = 40
                        }
                        ForEach(MuscleGroup.allCases, id: \.self) { muscle in
                            filterChip(title: muscle.label, isSelected: selectedMuscle == muscle) {
                                selectedMuscle = selectedMuscle == muscle ? nil : muscle
                                shownCount = 40
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Equipment Filter Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(title: "Any equipment", isSelected: selectedEquipment == nil) {
                            selectedEquipment = nil
                            shownCount = 40
                        }
                        ForEach(availableEquipment, id: \.self) { eq in
                            filterChip(title: eq.label, isSelected: selectedEquipment == eq) {
                                selectedEquipment = selectedEquipment == eq ? nil : eq
                                shownCount = 40
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Exercise Cards List
                LazyVStack(spacing: 8) {
                    // Custom Exercise Creation Card
                    customExerciseCard

                    // Filtered Exercises up to shownCount
                    ForEach(filteredExercises.prefix(shownCount), id: \.id) { ex in
                        exerciseRow(ex)
                    }

                    // Show More Button
                    if filteredExercises.count > shownCount {
                        Button {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            shownCount += 40
                        } label: {
                            Text("Show more")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(GymTheme.green)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 90)
        }
        .background(GymTheme.bg.ignoresSafeArea())
        .sheet(item: $selectedExerciseForDetail) { ex in
            ExerciseDetailSheet(exercise: ex)
        }
    }

    // MARK: - Filter Chip

    @ViewBuilder
    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    isSelected ? GymTheme.green : GymTheme.surface2,
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? .black : GymTheme.label2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Custom Exercise Card

    @ViewBuilder
    private var customExerciseCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(GymTheme.surface2)
                    .frame(width: 48, height: 48)
                Image(systemName: "sparkles")
                    .font(.system(size: 20))
                    .foregroundStyle(GymTheme.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Create your own exercise")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(GymTheme.label)
                Text("name + body part, no animation")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color(white: 0.55))
            }

            Spacer()

            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(white: 0.55))
        }
        .padding(12)
        .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Exercise Row

    @ViewBuilder
    private func exerciseRow(_ ex: Exercise) -> some View {
        Button {
            selectedExerciseForDetail = ex
        } label: {
            HStack(spacing: 12) {
                // Exercise Thumbnail Image
                ExerciseThumbnailView(urlString: ex.imagePaths.first, size: 48, cornerRadius: 10)

                VStack(alignment: .leading, spacing: 3) {
                    Text(ex.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(GymTheme.label)
                        .multilineTextAlignment(.leading)
                    Text("\(ex.primaryMuscle.label) · \(ex.equipment.label)")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color(white: 0.60))
                }

                Spacer()

                // + Plan Button
                Button {
                    selectedExerciseForDetail = ex
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Plan")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(GymTheme.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(GymTheme.green.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
