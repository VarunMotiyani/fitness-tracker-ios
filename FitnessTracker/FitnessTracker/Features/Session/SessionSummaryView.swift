import SwiftUI
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics

/// The end-of-session screen. Shown while `runner.phase == .summary` but
/// *before* `runner.finish(...)` has run — so the session is not yet persisted
/// as finished and `runner.lastSessionPRs` is still empty.
///
/// Two stages, driven by `saved`:
///   1. **capture** (`saved == false`) — per-exercise feel + note, an optional
///      "what got in the way?" reason when the session is incomplete, and an
///      overall note. "Save session" makes the single `runner.finish(...)` call
///      (persists the outcome, runs PR detection once) and flips `saved`.
///   2. **payoff** (`saved == true`) — new PRs and volume-vs-target per muscle,
///      then "Done" → `onClose()` (routed to `runner.closeSummary()`).
struct SessionSummaryView: View {
    let runner: SessionRunner
    let catalog: CatalogStore
    let onClose: () -> Void

    @State private var saved = false
    @State private var partialReason: PartialReason?
    @State private var overallNote = ""
    /// Local editing buffer for per-entry notes, keyed by `performedOrder` index.
    @State private var entryNotes: [Int: String] = [:]

    private var hasIncomplete: Bool {
        // F3: a skipped entry is not a performed entry, even though it carries
        // `stateRaw == .done`.
        runner.entriesInOrder.contains {
            $0.stateRaw != EntryState.done.rawValue || $0.skipped
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if saved {
                    payoffContent
                } else {
                    captureContent
                }
            }
            .padding()
        }
    }

    // MARK: - Stage 1: capture

    @ViewBuilder
    private var captureContent: some View {
        Text("How did that go?")
            .font(.title2.bold())

        ForEach(Array(runner.entriesInOrder.enumerated()), id: \.element.persistentModelID) { index, entry in
            entryFeedback(index: index, entry: entry)
        }

        if hasIncomplete {
            VStack(alignment: .leading, spacing: 8) {
                Text("What got in the way?")
                    .font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PartialReason.allCases, id: \.self) { reason in
                            Button(reason.label) {
                                partialReason = (partialReason == reason) ? nil : reason
                            }
                            .buttonStyle(.bordered)
                            .tint(partialReason == reason ? .accentColor : .secondary)
                        }
                    }
                }
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Anything to note?")
                .font(.headline)
            TextField("Overall note", text: $overallNote, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
        }

        Button {
            // F2: flush the local per-entry note buffer — a single-line
            // TextField in a ScrollView routinely loses focus without ever
            // firing `.onSubmit`, so "Save session" must persist it explicitly.
            for (i, text) in entryNotes where !text.isEmpty {
                runner.setEntryNote(entryIndex: i, text)
            }
            runner.finish(
                partialReason: partialReason,
                overallNote: overallNote.isEmpty ? nil : overallNote
            )
            saved = true
        } label: {
            Text("Save session")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func entryFeedback(index: Int, entry: CompletedEntryModel) -> some View {
        let current = Feel(rawValue: entry.feelRaw ?? "")
        VStack(alignment: .leading, spacing: 8) {
            Text(catalog.exercise(id: entry.exerciseID)?.name ?? entry.exerciseID)
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(Feel.allCases, id: \.self) { feel in
                    Button {
                        runner.setFeel(entryIndex: index, feel)
                    } label: {
                        Text(feel.label)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(current == feel ? .accentColor : .secondary)
                }
            }

            TextField("Note (optional)", text: noteBinding(index: index, entry: entry))
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    runner.setEntryNote(entryIndex: index, entryNotes[index] ?? "")
                }
        }
    }

    private func noteBinding(index: Int, entry: CompletedEntryModel) -> Binding<String> {
        Binding(
            get: { entryNotes[index] ?? entry.note ?? "" },
            set: { entryNotes[index] = $0 }
        )
    }

    // MARK: - Stage 2: payoff

    @ViewBuilder
    private var payoffContent: some View {
        Text("Session saved")
            .font(.title2.bold())

        // PRs
        VStack(alignment: .leading, spacing: 8) {
            Text("Personal records")
                .font(.headline)
            if runner.lastSessionPRs.isEmpty {
                Text("No PRs this session — still counts.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(runner.lastSessionPRs.enumerated()), id: \.offset) { _, pr in
                    HStack(spacing: 10) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                        Text("New \(catalog.exercise(id: pr.exerciseID)?.name ?? pr.exerciseID) PR — \(prValueString(pr))")
                            .font(.subheadline.weight(.medium))
                    }
                }
            }
        }

        // Volume vs target
        VStack(alignment: .leading, spacing: 8) {
            Text("Volume vs target")
                .font(.headline)
            let rows = volumeRows
            if rows.isEmpty {
                Text("No volume recorded.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows, id: \.muscle) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(row.muscle.label)
                            Spacer()
                            Text("\(row.logged) / \(row.target) sets")
                                .foregroundStyle(.secondary)
                            if row.target > 0, row.logged >= row.target {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .font(.subheadline)
                        ProgressView(
                            value: Double(min(row.logged, max(row.target, 1))),
                            total: Double(max(row.target, 1))
                        )
                    }
                }
            }
        }

        Button {
            onClose()
        } label: {
            Text("Done")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .padding(.top, 4)
    }

    // MARK: - Derived data

    private func prValueString(_ pr: PersonalRecord) -> String {
        switch pr.type {
        case .heaviestWeight, .estimated1RM:
            return "\(kgString(pr.value)) kg"
        case .repsAtWeight:
            return "\(pr.reps) reps @ \(kgString(pr.atLoadKg)) kg"
        }
    }

    private func kgString(_ v: Double) -> String {
        v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    private var loggedByMuscle: [MuscleGroup: Int] {
        guard let snap = runner.session?.toSnapshot() else { return [:] }
        let rollup = RollupComputer(catalog: catalog)
            .weeklyMuscleVolume(from: [snap], calendar: .isoUTC)
        return Dictionary(rollup.map { ($0.muscle, $0.sets) }, uniquingKeysWith: +)
    }

    private var targetByMuscle: [MuscleGroup: Int] {
        var result: [MuscleGroup: Int] = [:]
        for item in runner.finalized?.session.items ?? [] {
            guard let muscle = catalog.exercise(id: item.exerciseID)?.primaryMuscle else { continue }
            result[muscle, default: 0] += item.targetSets
        }
        return result
    }

    private var volumeRows: [(muscle: MuscleGroup, logged: Int, target: Int)] {
        let logged = loggedByMuscle
        let target = targetByMuscle
        let present = Set(logged.keys).union(target.keys)
        return MuscleGroup.allCases
            .filter(present.contains)
            .map { (muscle: $0, logged: logged[$0] ?? 0, target: target[$0] ?? 0) }
    }
}

// MARK: - Local display labels

private extension Feel {
    var label: String {
        switch self {
        case .easy:   "Easy"
        case .right:  "Right"
        case .brutal: "Brutal"
        }
    }
}

private extension PartialReason {
    var label: String {
        switch self {
        case .ranOutOfTime: "Ran out of time"
        case .tooTired:     "Too tired"
        case .painNiggle:   "Pain / niggle"
        case .gymCrowded:   "Gym crowded"
        case .notFeelingIt: "Not feeling it"
        case .other:        "Other"
        }
    }
}

// #Preview omitted — SessionSummaryView needs a live SessionRunner in .summary
// (an in-memory ModelContainer + a real start() + logged sets + requestSummary()),
// which isn't practical in a #Preview. Verified in-app at Task 12.
