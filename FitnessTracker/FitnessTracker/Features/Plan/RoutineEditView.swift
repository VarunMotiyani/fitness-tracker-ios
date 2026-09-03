import SwiftUI
import FitnessDomain
import ExerciseCatalog
import Metrics
import RuleEngine

public struct RoutineEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding public var routine: RoutineDraft
    public let catalog: CatalogStore
    public let onSave: (RoutineDraft) -> Void
    public let onDelete: (UUID) -> Void

    @State private var showingIconPicker = false
    @State private var showingAddExercise = false
    @State private var editingWrapper: ConfigWrapper? = nil
    @State private var showingDeleteAlert = false

    public init(
        routine: Binding<RoutineDraft>,
        catalog: CatalogStore,
        onSave: @escaping (RoutineDraft) -> Void,
        onDelete: @escaping (UUID) -> Void
    ) {
        self._routine = routine
        self.catalog = catalog
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var targetedMuscles: [MuscleGroup] {
        var muscles: Set<MuscleGroup> = []
        for exConfig in routine.exercises {
            if let exercise = catalog.exercise(id: exConfig.exerciseID) {
                muscles.insert(exercise.primaryMuscle)
                muscles.formUnion(exercise.secondaryMuscles)
            }
        }
        return Array(muscles)
    }

    public var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Button {
                        showingIconPicker = true
                    } label: {
                        Image(systemName: routine.iconName)
                            .font(.system(size: 24))
                            .foregroundStyle(GymTheme.green)
                            .frame(width: 44, height: 44)
                            .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    TextField("Routine Name", text: $routine.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(GymTheme.label)
                }
                .padding(.vertical, 4)
            }

            Section("Progression & Deload") {
                Picker("Progression Rule", selection: Binding(
                    get: { routine.policy ?? "doubleProgression" },
                    set: { routine.policy = $0 }
                )) {
                    Text("Double Progression").tag("doubleProgression")
                    Text("Linear Progression").tag("linear")
                    Text("Greyskull LP").tag("greyskull")
                    Text("None / Manual").tag("none")
                }

                Toggle("Exclude from automatic progression", isOn: $routine.excludeFromProgression)
                    .tint(GymTheme.green)
            }

            Section {
                if routine.exercises.isEmpty {
                    Text("No exercises added yet.")
                        .font(.subheadline)
                        .foregroundStyle(GymTheme.label3)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(routine.exercises.enumerated()), id: \.element.id) { index, exConfig in
                        let exercise = catalog.exercise(id: exConfig.exerciseID)
                        let name = exercise?.name ?? "Exercise"
                        
                        Button {
                            editingWrapper = ConfigWrapper(index: index, config: exConfig)
                        } label: {
                            HStack(spacing: 12) {
                                ExerciseThumbnailView(exercise: exercise)
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(GymTheme.label)
                                        
                                        if let sID = exConfig.supersetID, !sID.isEmpty {
                                            Label("Superset", systemImage: "link")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(GymTheme.sky)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(GymTheme.sky.opacity(0.15), in: Capsule())
                                        }
                                    }

                                    Text(summaryLine(for: exConfig))
                                        .font(.caption)
                                        .foregroundStyle(GymTheme.label3)
                                }

                                Spacer()

                                Button {
                                    toggleSuperset(at: index)
                                } label: {
                                    Image(systemName: exConfig.supersetID != nil ? "link.circle.fill" : "link.circle")
                                        .font(.system(size: 20))
                                        .foregroundStyle(exConfig.supersetID != nil ? GymTheme.sky : GymTheme.label3)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        routine.exercises.remove(atOffsets: indexSet)
                    }
                    .onMove { from, to in
                        routine.exercises.move(fromOffsets: from, toOffset: to)
                    }
                }

                Button {
                    showingAddExercise = true
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .foregroundStyle(GymTheme.green)
                }
            } header: {
                Text("Exercises (\(routine.exercises.count))")
            }

            if !targetedMuscles.isEmpty {
                Section("What this session hits") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                        ForEach(targetedMuscles, id: \.self) { muscle in
                            Text(muscle.rawValue.capitalized)
                                .font(.caption.bold())
                                .foregroundStyle(GymTheme.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity)
                                .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    HStack {
                        Spacer()
                        Text("Delete Routine")
                            .font(.headline)
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Edit Routine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    onSave(routine)
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showingIconPicker) {
            IconPickerSheet(selectedIcon: $routine.iconName)
        }
        .sheet(isPresented: $showingAddExercise) {
            ExercisePickerCatalogSheet(catalog: catalog) { pickedExercise in
                let newConfig = ExerciseConfig(
                    exerciseID: pickedExercise.id,
                    sets: 3,
                    reps: 10,
                    weightKg: pickedExercise.equipment == .bodyweight ? 0.0 : 20.0,
                    bodyweight: pickedExercise.equipment == .bodyweight
                )
                routine.exercises.append(newConfig)
                showingAddExercise = false
            }
        }
        .sheet(item: $editingWrapper) { wrapper in
            let exName = catalog.exercise(id: wrapper.config.exerciseID)?.name ?? "Exercise"
            ExerciseConfigSheet(
                exerciseName: exName,
                config: Binding(
                    get: {
                        if routine.exercises.indices.contains(wrapper.index) {
                            return routine.exercises[wrapper.index]
                        }
                        return wrapper.config
                    },
                    set: { updated in
                        if routine.exercises.indices.contains(wrapper.index) {
                            routine.exercises[wrapper.index] = updated
                        }
                    }
                ),
                onSave: { updated in
                    if routine.exercises.indices.contains(wrapper.index) {
                        routine.exercises[wrapper.index] = updated
                    }
                }
            )
        }
        .confirmationDialog("Delete \(routine.name)?", isPresented: $showingDeleteAlert, titleVisibility: .visible) {
            Button("Delete Routine", role: .destructive) {
                onDelete(routine.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private func summaryLine(for config: ExerciseConfig) -> String {
        if config.mode == "time" {
            return "\(config.sets) sets · \(config.sec)s hold"
        }
        if let minR = config.repsMin, let maxR = config.repsMax {
            let loadStr = config.bodyweight ? "BW" : "\(String(format: "%.1f", config.weightKg)) kg"
            return "\(config.sets) sets × \(minR)–\(maxR) reps · \(loadStr)"
        }
        let loadStr = config.bodyweight ? "BW" : "\(String(format: "%.1f", config.weightKg)) kg"
        return "\(config.sets) sets × \(config.reps) reps · \(loadStr)"
    }

    private func toggleSuperset(at index: Int) {
        if let current = routine.exercises[index].supersetID {
            routine.exercises[index].supersetID = nil
        } else {
            let sharedID = UUID().uuidString.prefix(8)
            routine.exercises[index].supersetID = String(sharedID)
            if index > 0 && routine.exercises[index - 1].supersetID == nil {
                routine.exercises[index - 1].supersetID = String(sharedID)
            } else if index + 1 < routine.exercises.count && routine.exercises[index + 1].supersetID == nil {
                routine.exercises[index + 1].supersetID = String(sharedID)
            }
        }
    }
}

public struct ConfigWrapper: Identifiable {
    public let index: Int
    public let config: ExerciseConfig
    public var id: UUID { config.id }

    public init(index: Int, config: ExerciseConfig) {
        self.index = index
        self.config = config
    }
}

public struct ExercisePickerCatalogSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let catalog: CatalogStore
    public let onSelect: (Exercise) -> Void

    @State private var searchText = ""
    @State private var selectedMuscle: MuscleGroup? = nil

    public init(catalog: CatalogStore, onSelect: @escaping (Exercise) -> Void) {
        self.catalog = catalog
        self.onSelect = onSelect
    }

    private var filteredExercises: [Exercise] {
        catalog.all.filter { ex in
            let matchesSearch = searchText.isEmpty || ex.name.localizedCaseInsensitiveContains(searchText)
            let matchesMuscle = selectedMuscle == nil || ex.primaryMuscle == selectedMuscle
            return matchesSearch && matchesMuscle
        }
    }

    public var body: some View {
        NavigationStack {
            List(filteredExercises) { exercise in
                Button {
                    onSelect(exercise)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        ExerciseThumbnailView(exercise: exercise)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(GymTheme.label)
                            Text("\(exercise.primaryMuscle.rawValue.capitalized) · \(exercise.equipment.rawValue.capitalized)")
                                .font(.caption)
                                .foregroundStyle(GymTheme.label3)
                        }

                        Spacer()

                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(GymTheme.green)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search 1,300+ exercises")
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
