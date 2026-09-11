import SwiftUI
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics
import RuleEngine
import Combine

private enum ActiveFocusSheet: Identifiable {
    case plateMath
    case mediaZoom(Exercise?)
    case exerciseDetail(Exercise)
    case exerciseNote(name: String, id: String, instruction: String?)
    case sessionNote
    case swapExercise(Exercise)
    case workingWeight(name: String, id: String, maxWeight: Double)

    var id: String {
        switch self {
        case .plateMath: return "plateMath"
        case .mediaZoom: return "mediaZoom"
        case .exerciseDetail(let ex): return "exerciseDetail_\(ex.id)"
        case .exerciseNote: return "exerciseNote"
        case .sessionNote: return "sessionNote"
        case .swapExercise(let ex): return "swapExercise_\(ex.id)"
        case .workingWeight: return "workingWeight"
        }
    }
}

private struct DraftSetRow: Identifiable {
    let id = UUID()
    var loadKg: Double
    var reps: Double
    var rir: Double?
    var isWarmup: Bool
}

/// Keeps the primary workout flow deterministic: completing an exercise moves
/// to the next entry when one exists, otherwise it enters the finish flow.
enum SessionAdvancePolicy {
    nonisolated static func nextIndex(currentIndex: Int, entryCount: Int) -> Int? {
        let nextIndex = currentIndex + 1
        guard currentIndex >= 0, nextIndex < entryCount else { return nil }
        return nextIndex
    }
}

/// Tactile Gym-Floor Workout Runner with complete UI parity:
/// - Session header: ✕ close, live elapsed timer mm:ss, sets-based progress bar n/N sets, ✓ finish.
/// - All-sets-editable interactive table with inline weight, reps, RIR steppers and ✓ check.
/// - Meta chips: Muscle · Equipment · Best PR.
/// - "Last time" recap line from history.
/// - "Why" autoregulation progression rationale banner.
/// - Superset linking with next exercise.
/// - Inline "🔥 Add warm-up set", "− Remove set", "+ Add set".
struct SessionFocusView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let runner: SessionRunner
    let catalog: CatalogStore
    var onOpenList: () -> Void = {}

    @Query private var personalRecords: [PersonalRecordModel]
    @Query(sort: \CompletedSessionModel.startedAt, order: .reverse)
    private var previousSessions: [CompletedSessionModel]

    @AppStorage("gym_working_weights_json") private var workingWeightsJSON: String = "{}"
    @AppStorage("gym_keep_awake") private var keepAwake: Bool = true
    @AppStorage("gym_timer_flash") private var timerFlash: Bool = true
    @AppStorage("gym_media_source") private var mediaSourceRaw: String = ExerciseMediaSource.gymVisual.rawValue

    // Draft interactive state for upcoming sets in current exercise
    @State private var draftRows: [DraftSetRow] = []
    @State private var targetTotalSets: Int = 3
    /// Memoized per exercise in `seedCurrentExercise()` — these scans touch
    /// every past session and must never run from `body` (they used to, at
    /// the elapsed timer's 1 Hz rate).
    @State private var lastTimeText: String?
    @State private var bestText: String?
    @State private var firstLoggedStart: Date?
    @State private var isSupersetWithNext: Bool = false
    @State private var restTimer = RestTimer()
    @State private var flashTriggerID = UUID()

    @State private var currentExerciseNote: String = ""
    @State private var currentExercisePin: Bool = false
    @State private var sessionNoteText: String = ""

    @State private var activeSheet: ActiveFocusSheet? = nil
    @State private var showExitDialog = false
    @State private var showCompleteDialog = false

    init(
        runner: SessionRunner,
        catalog: CatalogStore,
        onOpenList: @escaping () -> Void = {}
    ) {
        self.runner = runner
        self.catalog = catalog
        self.onOpenList = onOpenList
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Top session-level navigation header
                sessionTopHeader

                // Pinned Total-Set Progress Bar
                totalSetProgressBar

                // Main Exercise Scroll Body
                Group {
                    if let finalized = runner.finalized, let entry = runner.currentEntry {
                        let planned = finalized.session.items.first { $0.exerciseID == entry.exerciseID }
                        contentView(entry: entry, planned: planned, finalized: finalized)
                    } else {
                        ContentUnavailableView("No active exercise", systemImage: "dumbbell")
                    }
                }
            }
            .background(GymTheme.bg.ignoresSafeArea())

            if timerFlash {
                TimerFlashOverlay(triggerID: flashTriggerID)
            }
        }
        .background(GymTheme.bg.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if keepAwake {
                UIApplication.shared.isIdleTimerDisabled = true
            }
            seedCurrentExercise()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: runner.currentEntryIndex) { _, _ in
            seedCurrentExercise()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .plateMath:
                let activeWeight = draftRows.first?.loadKg ?? 60.0
                PlateMathSheet(initialWeight: activeWeight)
            case .mediaZoom(let ex):
                ExerciseMediaZoomSheet(exercise: ex)
            case .exerciseDetail(let ex):
                ExerciseDetailSheet(exercise: ex)
            case .exerciseNote(let name, _, let instruction):
                ExerciseNoteSheet(
                    exerciseName: name,
                    planNote: instruction,
                    standingNote: nil,
                    pinnedNote: nil,
                    todayNote: $currentExerciseNote,
                    notePin: $currentExercisePin
                )
            case .sessionNote:
                SessionNoteSheet(sessionNote: $sessionNoteText)
            case .swapExercise(let currentEx):
                ExerciseSwapSheet(currentExercise: currentEx, catalog: catalog) { replacement, _, _ in
                    runner.swapExercise(at: runner.currentEntryIndex, to: replacement.id)
                    seedCurrentExercise()
                }
            case .workingWeight(let name, let id, let maxW):
                WorkingWeightSheet(
                    exerciseName: name,
                    exerciseID: id,
                    initialWeight: maxW,
                    previousBest: nil,
                    onSave: { savedWeight in
                        saveWorkingWeight(exerciseID: id, weight: savedWeight)
                    }
                )
            }
        }
        .confirmationDialog("Leave Workout?", isPresented: $showExitDialog, titleVisibility: .visible) {
            Button("Leave Workout", role: .destructive) {
                dismiss()
            }
            Button("Resume Workout", role: .cancel) {}
        } message: {
            Text("Your logged sets are saved. You can resume this session anytime.")
        }
        .confirmationDialog("Finish Workout?", isPresented: $showCompleteDialog, titleVisibility: .visible) {
            Button("Finish & View Summary") {
                runner.markDone(entryIndex: runner.currentEntryIndex)
                runner.requestSummary()
            }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("Ready to wrap up and review your workout summary?")
        }
    }

    // MARK: - Top Session Header

    @ViewBuilder
    private var sessionTopHeader: some View {
        let routineName = sessionRoutineName
        let totalDoneSets = allLoggedSetsCount
        let totalTargetSets = totalSessionPlannedSets

        HStack(spacing: 12) {
            // Close / Minimize ✕ button
            Button {
                showExitDialog = true
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(GymTheme.label2)
                    .frame(width: 44, height: 44)
                    .background(GymTheme.surface2, in: Circle().inset(by: 4))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close workout")

            Spacer()

            // Center: Routine Name + Elapsed mm:ss + Total Sets — tap to see every
            // exercise in the session (done/in-progress/pending) and jump around.
            Button {
                onOpenList()
            } label: {
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Text(routineName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(GymTheme.label)
                        Image(systemName: "list.bullet")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(GymTheme.label3)
                    }
                    // The clock owns its own 1 Hz tick, so the per-second
                    // refresh invalidates this tiny Text, not the whole body.
                    HStack(spacing: 0) {
                        SessionElapsedClock(startDate: firstLoggedStart)
                        Text(" · \(totalDoneSets)/\(totalTargetSets) sets")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(GymTheme.label3)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Finish ✓ button
            Button {
                showCompleteDialog = true
            } label: {
                Image(systemName: "checkmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(GymTheme.green)
                    .frame(width: 44, height: 44)
                    .background(GymTheme.green.opacity(0.18), in: Circle().inset(by: 4))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Finish workout")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(GymTheme.bgElevated)
    }

    @ViewBuilder
    private var totalSetProgressBar: some View {
        let totalDoneSets = allLoggedSetsCount
        let totalTargetSets = max(1, totalSessionPlannedSets)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                Rectangle()
                    .fill(GymTheme.green)
                    .frame(width: geo.size.width * CGFloat(min(1.0, Double(totalDoneSets) / Double(totalTargetSets))))
            }
        }
        .frame(height: 3)
    }

    // MARK: - Main Scroll Body

    @ViewBuilder
    private func contentView(
        entry: CompletedEntryModel,
        planned: PlannedItem?,
        finalized: FinalizedSession
    ) -> some View {
        let exercise = catalog.exercise(id: entry.exerciseID)
        let loggedSets = entry.sets.sorted { $0.startedAt < $1.startedAt }
        let isAllDone = loggedSets.filter { !$0.isWarmup }.count >= targetTotalSets
        let rationale = finalized.perItemRationale[entry.exerciseID] ?? ""

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 1. Exercise Media Stage (Clean Light Stage + Expand Pill)
                mediaStageCard(exercise: exercise)

                // 2. Exercise Title + Info Button
                exerciseTitleHeader(exercise: exercise, entry: entry)

                // 3. Meta Chips (Muscle · Equipment · Best PR)
                metaChipsRow(exercise: exercise)

                // 4. "Last Time" Performance Recap (memoized per exercise)
                if let lastRecap = lastTimeText {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption)
                            .foregroundStyle(GymTheme.label3)
                        Text(lastRecap)
                            .font(.footnote.weight(.regular))
                            .foregroundStyle(GymTheme.label2)
                    }
                    .padding(.horizontal, 2)
                }

                // 5. Progression Rationale Banner ("Why")
                if !rationale.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(GymTheme.orange)
                        Text(rationale)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(GymTheme.orange)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GymTheme.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                }

                // 6. Superset Toggle Button
                supersetToggleButton

                // 7. Rest Timer Banner (if active)
                if restTimer.isRunning || restTimer.remaining > 0 {
                    RestTimerView(timer: restTimer)
                }

                // 8. Interactive all-sets editable table
                allSetsEditableTable(entry: entry, plannedRestSec: planned?.restSeconds ?? 90)

                // 9. Inline Set Actions: Warm-up / Remove / Add Set
                setActionsRow(entry: entry)

                // 10. Navigation Paging Footer
                navigationFooter(isAllDone: isAllDone)
            }
            .padding(16)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Subcomponents

    @ViewBuilder
    private func mediaStageCard(exercise: Exercise?) -> some View {
        // Free-exercise-db only has a same-named match for ~10% of exercises — most
        // will keep showing Gym Visual even with "Free" selected below.
        let alternateImages = exercise.flatMap { AlternateMediaLookup.imagePaths(forExerciseNamed: $0.name) }?
            .compactMap { URL(string: $0) }
        let preferFree = ExerciseMediaSource(rawValue: mediaSourceRaw) == .freeStatic
        let showingAlternate = preferFree && !(alternateImages ?? []).isEmpty

        VStack(alignment: .leading, spacing: 8) {
            Button {
                activeSheet = .mediaZoom(exercise)
            } label: {
                ZStack(alignment: .bottomLeading) {
                    Group {
                        if showingAlternate, let alternateImages {
                            CachedRemoteImageLoop(urls: alternateImages, maxPixelSize: 600)
                        } else if let gifPath = exercise?.gifImagePath, let url = URL(string: gifPath) {
                            AnimatedGifView(url: url)
                        } else {
                            ExerciseThumbnailView(exercise: exercise, size: 200)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Expand pill
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption2.weight(.bold))
                        Text("Expand")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.70), in: Capsule())
                    .padding(10)
                }
            }
            .buttonStyle(.plain)

            // Media-source picker, right here in the workout — same preference the
            // Exercises tab uses (`gym_media_source`), so setting it in either place
            // carries through to the other, and to every future workout.
            HStack(spacing: 8) {
                Picker("Exercise media", selection: $mediaSourceRaw) {
                    Text("Gym Visual").tag(ExerciseMediaSource.gymVisual.rawValue)
                    Text("Free").tag(ExerciseMediaSource.freeStatic.rawValue)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)

                if preferFree && alternateImages == nil {
                    Text("No free equivalent for this exercise")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(GymTheme.label3)
                }
            }
        }
    }

    @ViewBuilder
    private func exerciseTitleHeader(exercise: Exercise?, entry: CompletedEntryModel) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(exercise?.name ?? entry.exerciseID)
                .font(.title.weight(.bold))
                .foregroundStyle(GymTheme.label)
                .lineLimit(2)

            Spacer()

            // Info (ⓘ) Sheet Button
            if let exercise {
                Button {
                    activeSheet = .exerciseDetail(exercise)
                } label: {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundStyle(GymTheme.label3)
                }
                .buttonStyle(.plain)
            }

            // Note Pencil Button
            Button {
                let exName = catalog.exercise(id: entry.exerciseID)?.name ?? "Exercise"
                let instr = runner.finalized?.session.items.first { $0.exerciseID == entry.exerciseID }?.coachNote
                activeSheet = .exerciseNote(name: exName, id: entry.exerciseID, instruction: instr)
            } label: {
                Image(systemName: "pencil")
                    .font(.body)
                    .foregroundStyle(GymTheme.label3)
                    .padding(8)
                    .background(GymTheme.surface2, in: Circle())
            }
            .buttonStyle(.plain)

            // Plates Math Button
            Button {
                activeSheet = .plateMath
            } label: {
                Image(systemName: "circle.grid.2x1.fill")
                    .font(.subheadline)
                    .foregroundStyle(GymTheme.label3)
                    .padding(8)
                    .background(GymTheme.surface2, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func metaChipsRow(exercise: Exercise?) -> some View {
        HStack(spacing: 8) {
            if let muscle = exercise?.primaryMuscle {
                metaPill(title: muscle.rawValue.capitalized)
            }
            if let equipment = exercise?.equipment {
                metaPill(title: equipment.rawValue.capitalized)
            }
            if let best = bestText {
                metaPill(title: best)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func metaPill(title: String) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(GymTheme.label2)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(GymTheme.surface2, in: Capsule())
    }

    @ViewBuilder
    private var supersetToggleButton: some View {
        Button {
            isSupersetWithNext.toggle()
        } label: {
            HStack {
                Image(systemName: isSupersetWithNext ? "link" : "link.badge.plus")
                    .font(.footnote.weight(.bold))
                Text(isSupersetWithNext ? "Superset linked with next exercise" : "Make superset with next")
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(isSupersetWithNext ? GymTheme.sky : GymTheme.green)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSupersetWithNext ? GymTheme.sky : GymTheme.green.opacity(0.6), lineWidth: 1)
                    .background(isSupersetWithNext ? GymTheme.sky.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - All-Sets Editable Table

    @ViewBuilder
    private func allSetsEditableTable(entry: CompletedEntryModel, plannedRestSec: Int) -> some View {
        let loggedSets = entry.sets.sorted { $0.startedAt < $1.startedAt }

        VStack(spacing: 8) {
            // Table Column Headers
            HStack(spacing: 6) {
                Text("SET")
                    .frame(width: 34, alignment: .leading)
                Text("WEIGHT")
                    .frame(maxWidth: .infinity)
                Text("REPS")
                    .frame(maxWidth: .infinity)
                Text("RIR")
                    .frame(width: 76)
                Text("DONE")
                    .frame(width: 40, alignment: .trailing)
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(GymTheme.label3)
            .padding(.horizontal, 12)

            // Rows: Completed Sets + Remaining Pending Draft Sets
            ForEach(0..<targetTotalSets, id: \.self) { setIdx in
                if setIdx < loggedSets.count {
                    // Completed Set Row
                    completedSetRow(setIdx: setIdx, set: loggedSets[setIdx])
                } else {
                    // Editable Pending Set Row
                    let draftIdx = setIdx - loggedSets.count
                    if draftRows.indices.contains(draftIdx) {
                        pendingEditableSetRow(setIdx: setIdx, draftIdx: draftIdx, plannedRestSec: plannedRestSec)
                    }
                }
            }
        }
        .padding(12)
        .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func completedSetRow(setIdx: Int, set: LoggedSetModel) -> some View {
        HStack(spacing: 6) {
            // Badge
            ZStack {
                Circle()
                    .fill(set.isWarmup ? Color.orange : GymTheme.green)
                    .frame(width: 26, height: 26)
                Text(set.isWarmup ? "W" : "\(setIdx + 1)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
            }
            .frame(width: 34, alignment: .leading)

            // Weight
            Text(String(format: "%.1f kg", set.actualLoadKg))
                .font(.subheadline.weight(.semibold)).fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(GymTheme.label)
                .frame(maxWidth: .infinity)

            // Reps
            Text("\(set.actualReps)")
                .font(.subheadline.weight(.semibold)).fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(GymTheme.label)
                .frame(maxWidth: .infinity)

            // RIR
            if let rir = set.rir {
                Text(String(format: "%.1f", rir))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GymTheme.green)
                    .frame(width: 76)
            } else {
                Text("—")
                    .font(.subheadline)
                    .foregroundStyle(GymTheme.label3)
                    .frame(width: 76)
            }

            // Checked indicator
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(GymTheme.green)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(GymTheme.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func pendingEditableSetRow(setIdx: Int, draftIdx: Int, plannedRestSec: Int) -> some View {
        HStack(spacing: 6) {
            // Badge
            let isW = draftRows[draftIdx].isWarmup
            ZStack {
                Circle()
                    .stroke(isW ? Color.orange : GymTheme.green.opacity(0.6), lineWidth: 1.5)
                    .frame(width: 26, height: 26)
                Text(isW ? "W" : "\(setIdx + 1)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isW ? Color.orange : GymTheme.green)
            }
            .frame(width: 34, alignment: .leading)

            // Weight Stepper
            GymStepper(value: $draftRows[draftIdx].loadKg, step: 2.5, minVal: 0, maxVal: 500, unit: "kg", isDecimal: true,
                       a11yLabel: "weight in kilograms for set \(setIdx + 1)")

            // Reps Stepper
            GymStepper(value: $draftRows[draftIdx].reps, step: 1, minVal: 1, maxVal: 100, unit: "reps", isDecimal: false,
                       a11yLabel: "reps for set \(setIdx + 1)")

            // RIR Stepper (Always Accessible)
            EffortStepper(value: $draftRows[draftIdx].rir, mode: "rir")
                .frame(width: 76)

            // Log / Checkmark Action Button
            Button {
                logDraftSet(draftIdx: draftIdx, plannedRestSec: plannedRestSec)
            } label: {
                Image(systemName: "circle")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(GymTheme.green)
                    .frame(width: 44, height: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Log set \(setIdx + 1)")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Inline Set Actions (Item 3.12 Parity)

    @ViewBuilder
    private func setActionsRow(entry: CompletedEntryModel) -> some View {
        HStack(spacing: 12) {
            // 1. Add warm-up set
            Button {
                addWarmupSet()
            } label: {
                Label("Add warm-up set", systemImage: "flame.fill")
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(GymTheme.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(GymTheme.orange.opacity(0.14), in: Capsule())
            }

            // 2. Remove set
            if targetTotalSets > 1 {
                Button {
                    removeSet(entry: entry)
                } label: {
                    Label("Remove set", systemImage: "minus")
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(GymTheme.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(GymTheme.red.opacity(0.14), in: Capsule())
                }
            }

            // 3. Add set
            Button {
                addExtraSet()
            } label: {
                Label("Add set", systemImage: "plus")
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(GymTheme.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(GymTheme.green.opacity(0.14), in: Capsule())
            }

            Spacer()
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func navigationFooter(isAllDone: Bool) -> some View {
        HStack(spacing: 12) {
            if runner.currentEntryIndex > 0 {
                Button {
                    runner.currentEntryIndex -= 1
                } label: {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Previous")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }

            Button {
                advanceOrFinish()
            } label: {
                HStack {
                    Text(runner.currentEntryIndex < runner.entriesInOrder.count - 1 ? "Next Exercise" : "Finish Workout")
                    Image(systemName: runner.currentEntryIndex < runner.entriesInOrder.count - 1 ? "chevron.right" : "checkmark")
                }
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(isAllDone ? GymTheme.green : GymTheme.blue)
        }
        .padding(.top, 12)
    }

    // MARK: - Logic & Actions

    private var sessionRoutineName: String {
        guard let focusMuscles = runner.finalized?.session.focusMuscles else { return "Workout" }
        return RoutineNaming.dayName(for: focusMuscles)
    }

    private var earliestLoggedSetStart: Date? {
        runner.entriesInOrder.flatMap(\.sets).map(\.startedAt).min()
    }

    private var allLoggedSetsCount: Int {
        runner.entriesInOrder.reduce(0) { $0 + $1.sets.count }
    }

    private var totalSessionPlannedSets: Int {
        runner.finalized?.session.items.reduce(0) { $0 + $1.targetSets } ?? max(1, runner.entriesInOrder.count * 3)
    }

    private func seedCurrentExercise() {
        guard let entry = runner.currentEntry else { return }
        let plannedItem = runner.finalized?.session.items.first { $0.exerciseID == entry.exerciseID }
        let baseLoad = plannedItem?.targetLoadKg ?? defaultLoadKg(for: catalog.exercise(id: entry.exerciseID))
        let baseReps = Double(plannedItem?.targetReps.min ?? 8)
        let setsCount = plannedItem?.targetSets ?? 3

        let loggedCount = entry.sets.count
        targetTotalSets = max(setsCount, loggedCount)

        draftRows.removeAll()
        let neededDrafts = max(0, targetTotalSets - loggedCount)
        for _ in 0..<neededDrafts {
            draftRows.append(DraftSetRow(loadKg: baseLoad, reps: baseReps, rir: 2.0, isWarmup: false))
        }

        // Memoized history scans — computed once per exercise change instead of
        // on every body evaluation.
        lastTimeText = lastPerformanceText(exerciseID: entry.exerciseID)
        bestText = bestPerformanceText(exerciseID: entry.exerciseID)
        if firstLoggedStart == nil {
            firstLoggedStart = earliestLoggedSetStart
        }
    }

    private func logDraftSet(draftIdx: Int, plannedRestSec: Int) {
        guard draftRows.indices.contains(draftIdx) else { return }
        let draft = draftRows[draftIdx]

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        var flags = SetFlags()
        flags.isWarmup = draft.isWarmup

        runner.logSet(
            entryIndex: runner.currentEntryIndex,
            actualReps: Int(draft.reps),
            actualLoadKg: draft.loadKg,
            restBeforeSec: plannedRestSec,
            flags: flags
        )

        // Attach RIR
        if let currentEntry = runner.currentEntry, let lastSet = currentEntry.sets.last {
            lastSet.rir = draft.rir
        }

        // Remove the draft that was logged
        draftRows.remove(at: draftIdx)

        // The elapsed clock starts at the first logged set, not at screen open.
        if firstLoggedStart == nil {
            firstLoggedStart = earliestLoggedSetStart
        }

        // Start Rest Timer
        restTimer.start(seconds: plannedRestSec)
    }

    private func addWarmupSet() {
        guard let entry = runner.currentEntry else { return }
        let plannedItem = runner.finalized?.session.items.first { $0.exerciseID == entry.exerciseID }
        let baseLoad = (plannedItem?.targetLoadKg ?? defaultLoadKg(for: catalog.exercise(id: entry.exerciseID))) * 0.6
        draftRows.insert(DraftSetRow(loadKg: baseLoad, reps: 10, rir: nil, isWarmup: true), at: 0)
        targetTotalSets += 1
    }

    /// A starting weight for an exercise with no logged history yet, sized to what
    /// its equipment actually is — not a single flat number for everything, and not
    /// a blanket 0 for anything tagged bodyweight either: an assisted-machine
    /// movement (assisted pull-up/dip) uses that number as a real counterweight/
    /// assistance setting, where 0 would mean "no assistance," the opposite of what
    /// a first-time set on that machine should default to.
    private func defaultLoadKg(for exercise: Exercise?) -> Double {
        guard let exercise else { return 20.0 }
        if exercise.name.localizedCaseInsensitiveContains("assisted") {
            return 20.0 // a middling assistance/counterweight setting to start from
        }
        switch exercise.equipment {
        case .bodyweight, .bands, .stabilityBall, .rope, .roller, .cardioMachine:
            return 0.0 // no plates to add — bodyweight, or not a loaded implement at all
        case .dumbbell, .ezBar:
            return 10.0
        case .kettlebell:
            return 16.0
        case .medicineBall:
            return 5.0
        case .barbell, .cable, .machine, .smithMachine, .leverageMachine, .sled, .other:
            return 20.0
        }
    }

    private func addExtraSet() {
        let baseLoad = draftRows.last?.loadKg ?? 60.0
        let baseReps = draftRows.last?.reps ?? 8.0
        draftRows.append(DraftSetRow(loadKg: baseLoad, reps: baseReps, rir: 2.0, isWarmup: false))
        targetTotalSets += 1
    }

    private func removeSet(entry: CompletedEntryModel) {
        if !draftRows.isEmpty {
            draftRows.removeLast()
            targetTotalSets = max(1, targetTotalSets - 1)
        } else if !entry.sets.isEmpty {
            runner.removeLastSet(entryIndex: runner.currentEntryIndex)
            targetTotalSets = max(1, targetTotalSets - 1)
            // `firstLoggedStart` is cached (only ever set once from nil) so the
            // 1Hz clock doesn't re-scan every set every second — but that means
            // removing the session's only logged set left it pointing at a
            // deleted set's timestamp instead of resetting to "no sets yet".
            firstLoggedStart = earliestLoggedSetStart
        }
    }

    private func advanceOrFinish() {
        guard activeSheet == nil, !showCompleteDialog, !showExitDialog else { return }

        let nextIndex = SessionAdvancePolicy.nextIndex(
            currentIndex: runner.currentEntryIndex,
            entryCount: runner.entriesInOrder.count
        )

        // Working-weight capture only makes sense while the session continues —
        // presenting it and the finish dialog at once used to collide, and the
        // dialog was silently dropped, leaving the runner stuck on the last
        // exercise.
        if nextIndex != nil, let entry = runner.currentEntry {
            let maxW = entry.sets.filter { !$0.isWarmup }.map(\.actualLoadKg).max() ?? (draftRows.first?.loadKg ?? 60.0)
            let name = catalog.exercise(id: entry.exerciseID)?.name ?? "Exercise"
            activeSheet = .workingWeight(name: name, id: entry.exerciseID, maxWeight: maxW)
        }

        if let nextIndex {
            runner.markDone(entryIndex: runner.currentEntryIndex)
            // Continue in plan order. The exercise list remains available from
            // the session header, but is no longer an involuntary stop after
            // every completed exercise.
            runner.currentEntryIndex = nextIndex
        } else {
            runner.markDone(entryIndex: runner.currentEntryIndex)
            showCompleteDialog = true
        }
    }

    private func lastPerformanceText(exerciseID: String) -> String? {
        let finishedSessions = previousSessions.filter { $0.finishedAt != nil && $0.id != runner.session?.id }
        for sess in finishedSessions {
            for entry in sess.entries where entry.exerciseID == exerciseID {
                let workingSets = entry.sets.filter { !$0.isWarmup }.sorted { $0.startedAt < $1.startedAt }
                if !workingSets.isEmpty {
                    let dateStr = sess.startedAt.formatted(.dateTime.day().month(.abbreviated))
                    let setsSummary = workingSets.map { s in
                        let rirStr = s.rir != nil ? " (RIR \(String(format: "%.0f", s.rir!)))" : ""
                        return "\(String(format: "%.1f", s.actualLoadKg))×\(s.actualReps)\(rirStr)"
                    }.joined(separator: ", ")
                    return "Last time (\(dateStr)): \(setsSummary)"
                }
            }
        }
        return nil
    }

    private func bestPerformanceText(exerciseID: String) -> String? {
        let prs = personalRecords.filter { $0.exerciseID == exerciseID }
        if let best = prs.map(\.value).max() {
            return "Best: \(String(format: "%.1f", best)) kg"
        }
        return nil
    }

    private func saveWorkingWeight(exerciseID: String, weight: Double) {
        var weights: [String: Double] = [:]
        if let data = workingWeightsJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            weights = decoded
        }
        weights[exerciseID] = weight
        if let data = try? JSONEncoder().encode(weights),
           let str = String(data: data, encoding: .utf8) {
            workingWeightsJSON = str
        }
    }
}


/// Owns its own 1 Hz tick so the per-second refresh re-renders this
/// one-line Text instead of the whole session body.
private struct SessionElapsedClock: View {
    let startDate: Date?
    @State private var seconds: Int = 0
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(Self.format(seconds))
            .font(.caption.weight(.semibold))
            .fontDesign(.rounded)
            .monospacedDigit()
            .foregroundStyle(GymTheme.label3)
            .onReceive(tick) { _ in
                // Clock starts from your first logged set, not from when this
                // screen opened - the moment before your first rep shouldnt
                // count against the workout.
                let next = startDate.map { max(0, Int(Date().timeIntervalSince($0))) } ?? 0
                if next != seconds { seconds = next }
            }
    }

    private static func format(_ totalSeconds: Int) -> String {
        let min = totalSeconds / 60
        let sec = totalSeconds % 60
        return String(format: "%d:%02d", min, sec)
    }
}
