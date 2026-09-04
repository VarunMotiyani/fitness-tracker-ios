import SwiftUI
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics

private struct SwapTarget: Identifiable {
    let index: Int
    let exercise: Exercise
    var id: Int { index }
}

/// The "jump around" sheet for a live session: every finalized entry with a
/// state dot, tap-to-focus, drag-to-reorder, swipe-to-skip, and a "Finish
/// session" button pinned at the bottom. `onFinish` is routed by the container
/// to `runner.requestSummary()`.
struct SessionListView: View {
    let runner: SessionRunner
    let catalog: CatalogStore
    let onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showPartialConfirm = false
    @State private var swapTarget: SwapTarget?

    private var entries: [CompletedEntryModel] { runner.entriesInOrder }

    private var doneCount: Int {
        entries.filter { $0.stateRaw == EntryState.done.rawValue }.count
    }

    private var allDone: Bool {
        !entries.isEmpty && doneCount == entries.count
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(entries.enumerated()), id: \.element.persistentModelID) { index, entry in
                    row(index: index, entry: entry)
                }
                .onMove { source, dest in
                    // SwiftUI's `.onMove` `dest` is the index to insert *before*
                    // in the pre-move array; `runner.reorder(from:to:)` wants a
                    // final slot index. When moving downward the removal shifts
                    // everything after `s` left by one, so subtract one.
                    guard let s = source.first else { return }
                    let adjusted = (dest > s) ? dest - 1 : dest
                    runner.reorder(from: s, to: adjusted)
                }
            }
            .navigationTitle("Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
            .safeAreaInset(edge: .bottom) {
                finishButton
            }
            .confirmationDialog(
                "\(doneCount) of \(entries.count) done",
                isPresented: $showPartialConfirm,
                titleVisibility: .visible
            ) {
                Button("Finish as partial", role: .destructive) { dismiss(); onFinish() }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $swapTarget) { target in
                ExerciseSwapSheet(currentExercise: target.exercise, catalog: catalog) { replacement, _, _ in
                    runner.swapExercise(at: target.index, to: replacement.id)
                }
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(index: Int, entry: CompletedEntryModel) -> some View {
        let exercise = catalog.exercise(id: entry.exerciseID)
        Button {
            runner.currentEntryIndex = index
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ExerciseThumbnailView(exercise: exercise, size: 44, cornerRadius: 8)
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(stateColor(entry))
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                            .offset(x: 3, y: 3)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise?.name ?? entry.exerciseID)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(entry.sets.count == 1 ? "1 set" : "\(entry.sets.count) sets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if entry.skipped {
                    Text("skipped")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(.tertiarySystemBackground)))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Skip") { runner.markSkipped(entryIndex: index) }
                .tint(.orange)
            // Only offer a substitute for exercises you haven't started — swapping
            // one you've already logged sets against would orphan that history.
            if EntryState(rawValue: entry.stateRaw) != .done, entry.sets.isEmpty,
               let exercise = catalog.exercise(id: entry.exerciseID) {
                Button("Substitute") { swapTarget = SwapTarget(index: index, exercise: exercise) }
                    .tint(.blue)
            }
        }
    }

    private func stateColor(_ entry: CompletedEntryModel) -> Color {
        // F3: a skipped entry carries `stateRaw == .done` — branch on `skipped`
        // first so it doesn't render as a completed (green) row.
        if entry.skipped { return .secondary }
        switch EntryState(rawValue: entry.stateRaw) {
        case .inProgress: return .orange
        case .done: return .green
        default: return .gray
        }
    }

    // MARK: - Finish

    @ViewBuilder
    private var finishButton: some View {
        Button {
            if allDone {
                dismiss()          // F5: this sheet's presenter is torn down when the runner leaves .active
                onFinish()
            } else {
                showPartialConfirm = true
            }
        } label: {
            Text("Finish session")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .padding()
        .background(.bar)
    }
}

// #Preview omitted — needs a live SessionRunner (verified in-app at Task 12)
