import SwiftUI
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics

/// One exercise at a time: name + cue + image, the target line, a "why?"
/// rationale disclosure, the list of already-logged sets, a pre-filled
/// "log next set" row, a "Done" button, and Prev / Next paging. The toolbar
/// list button opens the session list (Task 9) as a sheet.
struct SessionFocusView: View {
    let runner: SessionRunner
    let catalog: CatalogStore
    /// Raised by the toolbar list button; the container owns the sheet (Task 9).
    var onOpenList: () -> Void = {}

    @State private var showWhy = false
    @State private var reps: Int = 8
    @State private var load: Double = 0
    @State private var warmup = false

    var body: some View {
        Group {
            if let finalized = runner.finalized, let entry = runner.currentEntry {
                let planned = finalized.session.items.first { $0.exerciseID == entry.exerciseID }
                content(entry: entry, planned: planned, finalized: finalized)
            } else {
                ContentUnavailableView("No exercise", systemImage: "dumbbell")
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onOpenList()
                } label: {
                    Label("Session list", systemImage: "list.bullet")
                }
            }
        }
        .onAppear { seedInputs() }
        .onChange(of: runner.currentEntryIndex) { _, _ in
            seedInputs()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(entry: CompletedEntryModel,
                         planned: PlannedItem?,
                         finalized: FinalizedSession) -> some View {
        let exercise = catalog.exercise(id: entry.exerciseID)
        let loggedSets = entry.sets.sorted { $0.startedAt < $1.startedAt }
        let workingSetCount = entry.sets.filter { !$0.isWarmup }.count
        let targetSets = planned?.targetSets ?? Int.max
        let doneReady = workingSetCount >= targetSets
        let rationale = finalized.perItemRationale[entry.exerciseID] ?? ""

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                exerciseHeader(exercise: exercise, entry: entry)

                Text(targetLine(planned: planned))
                    .font(.headline)
                    .foregroundStyle(.secondary)

                if !rationale.isEmpty {
                    whySection(rationale: rationale)
                }

                setList(loggedSets: loggedSets)

                logNextSetRow()

                doneButton(doneReady: doneReady)

                pager()
            }
            .padding()
        }
        .navigationTitle(exercise?.name ?? entry.exerciseID)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    @ViewBuilder
    private func exerciseHeader(exercise: Exercise?, entry: CompletedEntryModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // The app bundles no exercise images yet — grey placeholder for now.
            // TODO: render `exercise?.imagePaths` once media ships.
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .overlay(
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 56))
                        .foregroundStyle(.tertiary)
                )

            Text(exercise?.name ?? entry.exerciseID)
                .font(.title2.bold())

            if let cue = exercise?.instructions.first {
                Text(cue)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Why

    @ViewBuilder
    private func whySection(rationale: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { showWhy.toggle() }
            } label: {
                Label("why?", systemImage: showWhy ? "chevron.down" : "chevron.right")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.plain)

            if showWhy {
                Text(rationale)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Set list

    @ViewBuilder
    private func setList(loggedSets: [LoggedSetModel]) -> some View {
        if !loggedSets.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(loggedSets.enumerated()), id: \.element.persistentModelID) { index, set in
                    HStack {
                        Text("Set \(index + 1): \(set.actualReps) reps @ \(loadString(set.actualLoadKg)) kg")
                            .font(.subheadline)
                        if set.isWarmup {
                            Text("warm-up")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color(.tertiarySystemBackground)))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Log next set

    @ViewBuilder
    private func logNextSetRow() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log next set")
                .font(.headline)

            Stepper("Reps: \(reps)", value: $reps, in: 1...50)

            HStack {
                Text("Load: \(loadString(load)) kg")
                Spacer()
                Button {
                    load = max(0, load - 2.5)
                } label: {
                    Image(systemName: "minus.circle")
                }
                Button {
                    load = min(500, load + 2.5)
                } label: {
                    Image(systemName: "plus.circle")
                }
            }
            .font(.body)

            Toggle("Warm-up", isOn: $warmup)

            Button("Log set") {
                var flags = SetFlags()
                flags.isWarmup = warmup
                runner.logSet(
                    entryIndex: runner.currentEntryIndex,
                    actualReps: reps,
                    actualLoadKg: load,
                    restBeforeSec: 0, // TODO(task10): real rest interval from the rest timer
                    flags: flags
                )
                warmup = false
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }

    // MARK: - Done

    @ViewBuilder
    private func doneButton(doneReady: Bool) -> some View {
        let action = { runner.markDone(entryIndex: runner.currentEntryIndex) }
        Group {
            if doneReady {
                Button("Done", action: action)
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Done", action: action)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Pager

    @ViewBuilder
    private func pager() -> some View {
        HStack {
            Button("Previous") {
                if runner.currentEntryIndex > 0 { runner.currentEntryIndex -= 1 }
            }
            .disabled(runner.currentEntryIndex <= 0)

            Spacer()

            Button("Next") {
                if runner.currentEntryIndex < runner.entriesInOrder.count - 1 {
                    runner.currentEntryIndex += 1
                }
            }
            .disabled(runner.currentEntryIndex >= runner.entriesInOrder.count - 1)
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Helpers

    private func seedInputs() {
        let planned = runner.finalized?.session.items.first {
            $0.exerciseID == runner.currentEntry?.exerciseID
        }
        reps = planned?.targetReps.min ?? 8
        load = planned?.targetLoadKg ?? 0
        warmup = false
    }

    private func targetLine(planned: PlannedItem?) -> String {
        let sets = planned?.targetSets ?? 0
        let lo = planned?.targetReps.min ?? 0
        let hi = planned?.targetReps.max ?? 0
        let loadSuffix = planned?.targetLoadKg.map { " @ \(loadString($0)) kg" } ?? ""
        return "\(sets) × \(lo)–\(hi)\(loadSuffix)"
    }

    private func loadString(_ kg: Double) -> String {
        kg.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(kg))
            : String(format: "%.1f", kg)
    }
}

// #Preview omitted — SessionFocusView needs a live, started SessionRunner
// (an in-memory ModelContainer + a completed `start(...)`), which isn't
// practical in a #Preview. Verified via the app at Task 12.
