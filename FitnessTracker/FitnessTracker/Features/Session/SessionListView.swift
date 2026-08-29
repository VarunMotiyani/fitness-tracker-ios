import SwiftUI
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics

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
                Button("Finish as partial", role: .destructive) { onFinish() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(index: Int, entry: CompletedEntryModel) -> some View {
        Button {
            runner.currentEntryIndex = index
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(stateColor(entry))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(catalog.exercise(id: entry.exerciseID)?.name ?? entry.exerciseID)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text("\(entry.sets.count) sets")
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
        }
    }

    private func stateColor(_ entry: CompletedEntryModel) -> Color {
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
