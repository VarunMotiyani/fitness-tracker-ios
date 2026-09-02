import SwiftUI
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics

/// Tactile Gym-Floor Workout Runner matching openGym's Set Table and live mechanics.
struct SessionFocusView: View {
    let runner: SessionRunner
    let catalog: CatalogStore
    var onOpenList: () -> Void = {}

    @State private var reps: Double = 8
    @State private var load: Double = 60.0
    @State private var warmup = false
    @State private var restTimer = RestTimer()
    @State private var showPlateMath = false
    @State private var showWhy = false

    var body: some View {
        Group {
            if let finalized = runner.finalized, let entry = runner.currentEntry {
                let planned = finalized.session.items.first { $0.exerciseID == entry.exerciseID }
                content(entry: entry, planned: planned, finalized: finalized)
            } else {
                ContentUnavailableView("No active exercise", systemImage: "dumbbell")
            }
        }
        .sheet(isPresented: $showPlateMath) {
            PlateMathSheet(initialWeight: load)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onOpenList()
                } label: {
                    Label("All Exercises", systemImage: "list.bullet")
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
    private func content(
        entry: CompletedEntryModel,
        planned: PlannedItem?,
        finalized: FinalizedSession
    ) -> some View {
        let exercise = catalog.exercise(id: entry.exerciseID)
        let loggedSets = entry.sets.sorted { $0.startedAt < $1.startedAt }
        let targetSets = planned?.targetSets ?? 3
        let workingSetCount = loggedSets.filter { !$0.isWarmup }.count
        let isAllDone = workingSetCount >= targetSets
        let rationale = finalized.perItemRationale[entry.exerciseID] ?? ""

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Exercise Header & Target Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise?.name ?? entry.exerciseID)
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                            if let planned {
                                Text("\(planned.targetSets) sets × \(planned.targetReps.min)–\(planned.targetReps.max) reps · rest \(planned.restSeconds)s")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            showPlateMath = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "circle.grid.2x1.fill")
                                Text("Plates")
                            }
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(white: 0.20), in: Capsule())
                            .foregroundStyle(.white)
                        }
                    }

                    // AI Coach Note & Why Disclosure
                    if let note = planned?.coachNote, !note.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.caption)
                                .foregroundStyle(.purple)
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(Color(white: 0.8))
                        }
                    }

                    if !rationale.isEmpty {
                        DisclosureGroup(isExpanded: $showWhy) {
                            Text(rationale)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        } label: {
                            Text("Why this prescription?")
                                .font(.caption.bold())
                                .foregroundStyle(.purple)
                        }
                    }
                }
                .padding(14)
                .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 14))

                // Rest Timer Banner (if active)
                if restTimer.isRunning || restTimer.remaining > 0 {
                    RestTimerView(timer: restTimer)
                        .padding(.horizontal, 4)
                }

                // Interactive Set Table Header
                HStack(spacing: 8) {
                    Text("SET")
                        .frame(width: 36, alignment: .leading)
                    Text("WEIGHT")
                        .frame(maxWidth: .infinity)
                    Text("REPS")
                        .frame(maxWidth: .infinity)
                    Text("STATUS")
                        .frame(width: 50, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(white: 0.5))
                .padding(.horizontal, 8)

                // Already Logged Sets Rows
                ForEach(Array(loggedSets.enumerated()), id: \.offset) { idx, set in
                    HStack(spacing: 8) {
                        // Set number badge
                        ZStack {
                            Circle()
                                .fill(set.isWarmup ? Color.orange : Color.green)
                                .frame(width: 28, height: 28)
                            Text(set.isWarmup ? "W" : "\(idx + 1)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.black)
                        }
                        .frame(width: 36, alignment: .leading)

                        // Weight
                        Text(String(format: "%.1f kg", set.actualLoadKg))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)

                        // Reps
                        Text("\(set.actualReps) reps")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)

                        // Done icon
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.green)
                            .frame(width: 50, alignment: .trailing)
                    }
                    .padding(12)
                    .background(Color(white: 0.10), in: RoundedRectangle(cornerRadius: 10))
                }

                // Next Set to Log Row
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("LOG NEXT SET")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.green)
                        Spacer()
                        Toggle("Warmup", isOn: $warmup)
                            .toggleStyle(.button)
                            .tint(.orange)
                            .font(.caption.bold())
                    }

                    HStack(spacing: 8) {
                        // Current Set Number
                        ZStack {
                            Circle()
                                .fill(warmup ? Color.orange.opacity(0.3) : Color.green.opacity(0.3))
                                .frame(width: 32, height: 32)
                            Text(warmup ? "W" : "\(loggedSets.count + 1)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(warmup ? .orange : .green)
                        }
                        .frame(width: 36, alignment: .leading)

                        // Weight Stepper
                        GymStepper(value: $load, step: 2.5, minVal: 0, maxVal: 500, unit: "kg", isDecimal: true)

                        // Reps Stepper
                        GymStepper(value: $reps, step: 1, minVal: 1, maxVal: 100, unit: "reps", isDecimal: false)

                        // Complete Checkmark Button
                        Button {
                            logCurrentSet(plannedRestSec: planned?.restSeconds ?? 90)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 42, height: 42)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.black)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green.opacity(0.4), lineWidth: 1.5)
                )

                // Navigation Paging (Prev / Next / Finish)
                HStack(spacing: 12) {
                    if runner.currentEntryIndex > 0 {
                        Button {
                            runner.currentEntryIndex -= 1
                        } label: {
                            HStack {
                                Image(systemName: "chevron.left")
                                Text("Previous")
                            }
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                    }

                    Button {
                        if runner.currentEntryIndex < runner.entriesInOrder.count - 1 {
                            runner.markDone(entryIndex: runner.currentEntryIndex)
                            runner.currentEntryIndex += 1
                        } else {
                            runner.markDone(entryIndex: runner.currentEntryIndex)
                            runner.requestSummary()
                        }
                    } label: {
                        HStack {
                            Text(runner.currentEntryIndex < runner.entriesInOrder.count - 1 ? "Next Exercise" : "Finish Workout")
                            Image(systemName: runner.currentEntryIndex < runner.entriesInOrder.count - 1 ? "chevron.right" : "checkmark")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isAllDone ? .green : .blue)
                }
                .padding(.top, 8)
            }
            .padding(16)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(exercise?.name ?? entry.exerciseID)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func seedInputs() {
        guard let entry = runner.currentEntry else { return }
        let plannedItem = runner.finalized?.session.items.first { $0.exerciseID == entry.exerciseID }
        load = plannedItem?.targetLoadKg ?? 60.0
        reps = Double(plannedItem?.targetReps.min ?? 8)
        warmup = false
    }

    private func logCurrentSet(plannedRestSec: Int) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        var flags = SetFlags()
        flags.isWarmup = warmup
        runner.logSet(
            entryIndex: runner.currentEntryIndex,
            actualReps: Int(reps),
            actualLoadKg: load,
            restBeforeSec: 0,
            flags: flags
        )

        // Launch Rest Timer
        restTimer.start(seconds: plannedRestSec)
    }
}
