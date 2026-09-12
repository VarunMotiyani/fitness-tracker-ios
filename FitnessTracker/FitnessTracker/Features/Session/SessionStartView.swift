import SwiftUI
import FitnessDomain
import ExerciseCatalog
import UniformTypeIdentifiers

/// First screen of the session runner: choose how much time you have, review
/// today's exercises, and make one-off edits before starting.
///
/// Edits are intentionally scoped to this session. The recurring weekly plan
/// is never mutated from this screen.
struct SessionStartView: View {
    let planned: PlannedSession
    let catalog: CatalogStore
    let onPrepare: (PlannedSession, Int) -> Void
    let onClose: () -> Void
    let onStart: (PlannedSession, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: SessionStartDraft
    @State private var minutes: Int = 60
    @State private var showsCustomTime = false
    @State private var showsExercisePicker = false
    @State private var selectedExerciseForDetail: Exercise?
    @State private var selectedExerciseIndex: Int?
    @State private var replacementIndex: Int?
    @State private var draggedIndex: Int?

    private let timeChips = [45, 60, 90]

    init(
        planned: PlannedSession,
        catalog: CatalogStore,
        onPrepare: @escaping (PlannedSession, Int) -> Void = { _, _ in },
        onClose: @escaping () -> Void = {},
        onStart: @escaping (PlannedSession, Int) -> Void
    ) {
        self.planned = planned
        self.catalog = catalog
        self.onPrepare = onPrepare
        self.onClose = onClose
        self.onStart = onStart
        _draft = State(initialValue: SessionStartDraft(items: planned.items))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                timeSection
                exerciseListSection
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                onStart(draft.plannedSession(basedOn: planned), minutes)
            } label: {
                Text("Start")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .background(.bar)
        }
        .task {
            prepareCurrentSession()
        }
        .onChange(of: draft) { _, _ in
            prepareCurrentSession()
        }
        .onChange(of: minutes) { _, _ in
            prepareCurrentSession()
        }
        .navigationTitle("Session \(planned.order + 1)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if SessionExitPolicy.startScreenRequiresConfirmation {
                        dismiss()
                    } else {
                        // Explicitly dismiss the full-screen session rather
                        // than relying on the nested NavigationStack's dismiss.
                        onClose()
                    }
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Close workout setup")
            }
        }
        .sheet(item: $selectedExerciseForDetail) { exercise in
            ExerciseDetailSheet(
                exercise: exercise,
                onReplaceForToday: {
                    replacementIndex = selectedExerciseIndex
                    selectedExerciseForDetail = nil
                    showsExercisePicker = true
                },
                onRemoveFromToday: {
                    guard let index = selectedExerciseIndex,
                          draft.remove(at: index) != nil else { return false }
                    selectedExerciseIndex = nil
                    return true
                }
            )
        }
        .sheet(isPresented: $showsExercisePicker) {
            SessionExercisePickerSheet(
                catalog: catalog,
                focusMuscles: planned.focusMuscles,
                existingExerciseIDs: existingExerciseIDsForPicker
            ) { exercise in
                if let replacementIndex {
                    draft.replace(at: replacementIndex, with: exercise.id)
                    self.replacementIndex = nil
                } else {
                    draft.append(defaultItem(for: exercise))
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Session \(planned.order + 1)")
                .font(.largeTitle.bold())
            if !planned.focusMuscles.isEmpty {
                Text(planned.focusMuscles.map(\.label).joined(separator: ", "))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Text("\(previewItems.count) exercises  ·  ~\(estimatedMinutes) min")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            if previewItems.count < draft.items.count {
                Text("Showing the first \(previewItems.count) to fit \(minutes) min")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Time

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time available")
                .font(.headline)
            HStack(spacing: 12) {
                ForEach(timeChips, id: \.self) { value in
                    timeChip(title: "\(value)", selected: !showsCustomTime && minutes == value) {
                        showsCustomTime = false
                        minutes = value
                    }
                }
                timeChip(title: "Custom", selected: showsCustomTime) {
                    showsCustomTime = true
                }
            }
            if showsCustomTime {
                Stepper("\(minutes) min", value: $minutes, in: 30...150, step: 5)
                    .padding(.top, 4)
            }
        }
    }

    private func timeChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(selected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
                )
                .overlay(
                    Capsule().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Exercise List

    private var exerciseListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("Exercises")
                    .font(.headline)
                Spacer()
                Button {
                    showsExercisePicker = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
                .accessibilityLabel("Add exercise to this session")
            }

            Text("Hold the handle to reorder")
                .font(.caption)
                .foregroundStyle(.secondary)

            if draft.items.isEmpty {
                ContentUnavailableView {
                    Label("No exercises yet", systemImage: "dumbbell")
                } description: {
                    Text("Add an exercise to build today's session.")
                } actions: {
                    Button("Add exercise") { showsExercisePicker = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(previewItems.enumerated()), id: \.offset) { index, item in
                        exerciseRow(item: item, index: index)
                        if index < previewItems.count - 1 { Divider() }
                    }
                }
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.secondarySystemBackground))
                )

                if previewItems.count < draft.items.count {
                    Label(
                        "\(draft.items.count - previewItems.count) more \(draft.items.count - previewItems.count == 1 ? "exercise" : "exercises") won't fit in \(minutes) min",
                        systemImage: "clock"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 4)
                }
            }
        }
    }

    private func exerciseRow(item: PlannedItem, index: Int) -> some View {
        HStack(spacing: 10) {
            Button {
                selectedExerciseIndex = index
                selectedExerciseForDetail = catalog.exercise(id: item.exerciseID)
            } label: {
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, alignment: .leading)
                    ExerciseThumbnailView(exercise: catalog.exercise(id: item.exerciseID), size: 44, cornerRadius: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(catalog.exercise(id: item.exerciseID)?.name ?? item.exerciseID)
                            .font(.subheadline.weight(.medium))
                            .multilineTextAlignment(.leading)
                        Text("\(item.targetSets) sets · \(item.targetReps.min)–\(item.targetReps.max) reps")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View \(catalog.exercise(id: item.exerciseID)?.name ?? item.exerciseID) details")

            Image(systemName: "line.3.horizontal")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .onDrag {
                    draggedIndex = index
                    return NSItemProvider(object: NSString(string: item.exerciseID))
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: ExerciseReorderDropDelegate(
                        targetIndex: index,
                        draggedIndex: $draggedIndex,
                        draft: $draft
                    )
                )
                .accessibilityLabel("Reorder \(catalog.exercise(id: item.exerciseID)?.name ?? item.exerciseID)")
                .accessibilityHint("Long press and drag up or down")
        }
        .padding(.vertical, 10)
    }

    // MARK: - Estimate

    /// The session runner trims trailing items to fit the selected time. Keep
    /// the setup preview consistent, but never change the user's edited order.
    private var previewItems: [PlannedItem] {
        SessionStartPlanning.previewItems(draft.items, minutes: minutes)
    }

    private func estimatedMinutes(for items: [PlannedItem]) -> Double {
        SessionStartPlanning.estimatedMinutes(for: items)
    }

    private var estimatedMinutes: Int {
        Int(estimatedMinutes(for: previewItems).rounded())
    }

    private func defaultItem(for exercise: Exercise) -> PlannedItem {
        PlannedItem(
            exerciseID: exercise.id,
            targetSets: 3,
            targetReps: RepRange(min: 8, max: 12),
            targetLoadKg: nil,
            restSeconds: 90,
            coachNote: ""
        )
    }

    private var existingExerciseIDsForPicker: Set<String> {
        var ids = Set(draft.items.map(\.exerciseID))
        if let replacementIndex, draft.items.indices.contains(replacementIndex) {
            ids.remove(draft.items[replacementIndex].exerciseID)
        }
        return ids
    }

    private func prepareCurrentSession() {
        onPrepare(draft.plannedSession(basedOn: planned), minutes)
    }
}

/// Focus-aware picker for adding an exercise to today's session. It starts on
/// the planned muscle groups, while search still lets the user find any catalog
/// entry when the plan needs an intentional exception.
private struct SessionExercisePickerSheet: View {
    let catalog: CatalogStore
    let focusMuscles: [MuscleGroup]
    let existingExerciseIDs: Set<String>
    let onSelect: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredExercises: [Exercise] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let focus = Set(focusMuscles)
        return catalog.all
            .filter { !existingExerciseIDs.contains($0.id) }
            .filter { focus.isEmpty || focus.contains($0.primaryMuscle) || $0.secondaryMuscles.contains(where: focus.contains) }
            .filter { query.isEmpty || $0.name.lowercased().contains(query) }
            .sorted { ($0.primaryMuscle.label, $0.name) < ($1.primaryMuscle.label, $1.name) }
    }

    var body: some View {
        NavigationStack {
            List(filteredExercises, id: \.id) { exercise in
                Button {
                    onSelect(exercise)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        ExerciseThumbnailView(exercise: exercise, size: 48, cornerRadius: 10)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(exercise.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("\(exercise.primaryMuscle.label) · \(exercise.equipment.label)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.tint)
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if filteredExercises.isEmpty {
                    ContentUnavailableView(
                        "No matching exercises",
                        systemImage: "magnifyingglass",
                        description: Text("Try another search or broaden the exercise focus.")
                    )
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// Native drag/drop reordering delegate. The drag starts only after the user
/// long-presses the hamburger handle, matching familiar iOS list behavior.
private struct ExerciseReorderDropDelegate: DropDelegate {
    let targetIndex: Int
    @Binding var draggedIndex: Int?
    @Binding var draft: SessionStartDraft

    func dropEntered(info: DropInfo) {
        guard let sourceIndex = draggedIndex,
              sourceIndex != targetIndex,
              draft.items.indices.contains(sourceIndex),
              draft.items.indices.contains(targetIndex) else { return }

        withAnimation(.snappy) {
            draft.move(from: sourceIndex, to: targetIndex)
            draggedIndex = targetIndex
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedIndex = nil
        return true
    }
}

#Preview {
    let planned = PlannedSession(
        id: UUID(), order: 0, focusMuscles: [.chest, .triceps, .shoulders], items: [
            PlannedItem(exerciseID: "bench-press", targetSets: 4,
                        targetReps: RepRange(min: 6, max: 8), targetLoadKg: 60,
                        restSeconds: 150, coachNote: "Controlled tempo."),
            PlannedItem(exerciseID: "incline-db-press", targetSets: 3,
                        targetReps: RepRange(min: 8, max: 12), targetLoadKg: 24,
                        restSeconds: 120, coachNote: "Full stretch at the bottom."),
            PlannedItem(exerciseID: "cable-fly", targetSets: 3,
                        targetReps: RepRange(min: 12, max: 15), targetLoadKg: nil,
                        restSeconds: 75, coachNote: "Squeeze and hold."),
        ]
    )
    return NavigationStack {
        SessionStartView(planned: planned, catalog: CatalogStore(exercises: [])) { _, _ in }
    }
}
