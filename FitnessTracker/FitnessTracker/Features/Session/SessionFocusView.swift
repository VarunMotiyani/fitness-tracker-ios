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
    @State private var elapsedSeconds: Int = 0
    @State private var isSupersetWithNext: Bool = false
    @State private var restTimer = RestTimer()
    @State private var flashTriggerID = UUID()

    @State private var currentExerciseNote: String = ""
    @State private var currentExercisePin: Bool = false
    @State private var sessionNoteText: String = ""

    @State private var activeSheet: ActiveFocusSheet? = nil
    @State private var showExitDialog = false
    @State private var showCompleteDialog = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
                // Top Session-Level Navigation Header (openGym Parity)
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
        .onReceive(timer) { _ in
            // Clock starts from your first logged set, not from when this screen
            // opened — you need a moment to look at the exercise before you actually
            // start, and that shouldn't count against the workout's elapsed time.
            if let start = firstLoggedSetTime {
                elapsedSeconds = max(0, Int(Date().timeIntervalSince(start)))
            } else {
                elapsedSeconds = 0
            }
        }
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
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(GymTheme.label2)
                    .frame(width: 36, height: 36)
                    .background(GymTheme.surface2, in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            // Center: Routine Name + Elapsed mm:ss + Total Sets — tap to see every
            // exercise in the session (done/in-progress/pending) and jump around.
            Button {
                onOpenList()
            } label: {
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Text(routineName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(GymTheme.label)
                        Image(systemName: "list.bullet")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(GymTheme.label3)
                    }
                    Text("\(formattedElapsedTime) · \(totalDoneSets)/\(totalTargetSets) sets")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(GymTheme.label3)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Finish ✓ button
            Button {
                showCompleteDialog = true
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(GymTheme.green)
                    .frame(width: 36, height: 36)
                    .background(GymTheme.green.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
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

                // 4. "Last Time" Performance Recap
                if let lastRecap = lastPerformanceText(exerciseID: entry.exerciseID) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12))
                            .foregroundStyle(GymTheme.label3)
                        Text(lastRecap)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(GymTheme.label2)
                    }
                    .padding(.horizontal, 2)
                }

                // 5. Progression Rationale Banner ("Why")
                if !rationale.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(GymTheme.orange)
                        Text(rationale)
                            .font(.system(size: 13, weight: .medium))
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

                // 8. Interactive All-Sets Editable Table (openGym Item 3.10)
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
        let alternateImages = exercise.flatMap { AlternateMediaLookup.imagePaths(forExerciseNamed: $0.name) }
        let preferFree = ExerciseMediaSource(rawValue: mediaSourceRaw) == .freeStatic
        let showingAlternate = preferFree && alternateImages != nil

        VStack(alignment: .leading, spacing: 8) {
            Button {
                activeSheet = .mediaZoom(exercise)
            } label: {
                ZStack(alignment: .bottomLeading) {
                    Group {
                        if showingAlternate, let firstAlt = alternateImages?.first, let url = URL(string: firstAlt) {
                            AsyncImage(url: url) { phase in
                                if case .success(let image) = phase {
                                    image.resizable().scaledToFit()
                                } else {
                                    ProgressView()
                                }
                            }
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
                            .font(.system(size: 10, weight: .bold))
                        Text("Expand")
                            .font(.system(size: 11, weight: .bold))
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
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(GymTheme.label3)
                }
            }
        }
    }

    @ViewBuilder
    private func exerciseTitleHeader(exercise: Exercise?, entry: CompletedEntryModel) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(exercise?.name ?? entry.exerciseID)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(GymTheme.label)
                .lineLimit(2)

            Spacer()

            // Info (ⓘ) Sheet Button
            if let exercise {
                Button {
                    activeSheet = .exerciseDetail(exercise)
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 20))
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
                    .font(.system(size: 16))
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
                    .font(.system(size: 14))
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
            if let entry = runner.currentEntry, let best = bestPerformanceText(exerciseID: entry.exerciseID) {
                metaPill(title: best)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func metaPill(title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
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
                    .font(.system(size: 13, weight: .bold))
                Text(isSupersetWithNext ? "Superset linked with next exercise" : "Make superset with next")
                    .font(.system(size: 13, weight: .semibold))
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

    // MARK: - All-Sets Editable Table (openGym Item 3.10 Parity)

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
            .font(.system(size: 11, weight: .bold))
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
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
            }
            .frame(width: 34, alignment: .leading)

            // Weight
            Text(String(format: "%.1f kg", set.actualLoadKg))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(GymTheme.label)
                .frame(maxWidth: .infinity)

            // Reps
            Text("\(set.actualReps)")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(GymTheme.label)
                .frame(maxWidth: .infinity)

            // RIR
            if let rir = set.rir {
                Text(String(format: "%.1f", rir))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GymTheme.green)
                    .frame(width: 76)
            } else {
                Text("—")
                    .font(.system(size: 14))
                    .foregroundStyle(GymTheme.label3)
                    .frame(width: 76)
            }

            // Checked indicator
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24))
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
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isW ? Color.orange : GymTheme.green)
            }
            .frame(width: 34, alignment: .leading)

            // Weight Stepper
            GymStepper(value: $draftRows[draftIdx].loadKg, step: 2.5, minVal: 0, maxVal: 500, unit: "kg", isDecimal: true)

            // Reps Stepper
            GymStepper(value: $draftRows[draftIdx].reps, step: 1, minVal: 1, maxVal: 100, unit: "reps", isDecimal: false)

            // RIR Stepper (Always Accessible)
            EffortStepper(value: $draftRows[draftIdx].rir, mode: "rir")
                .frame(width: 76)

            // Log / Checkmark Action Button
            Button {
                logDraftSet(draftIdx: draftIdx, plannedRestSec: plannedRestSec)
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(GymTheme.green)
                    .frame(width: 44, height: 38, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
                    .font(.system(size: 12, weight: .bold))
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
                        .font(.system(size: 12, weight: .bold))
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
                    .font(.system(size: 12, weight: .bold))
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
                    .font(.system(size: 15, weight: .semibold))
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
                .font(.system(size: 15, weight: .bold))
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
        if let plannedID = runner.session?.plannedSessionID,
           let items = runner.finalized?.session.items {
            if items.first?.exerciseID == "0025" { return "Push Day" }
            if items.first?.exerciseID == "2330" { return "Pull Day" }
            if items.first?.exerciseID == "0043" { return "Legs Day" }
        }
        return "Workout Session"
    }

    private var formattedElapsedTime: String {
        let min = elapsedSeconds / 60
        let sec = elapsedSeconds % 60
        return String(format: "%d:%02d", min, sec)
    }

    private var firstLoggedSetTime: Date? {
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
        }
    }

    private func advanceOrFinish() {
        if let entry = runner.currentEntry {
            let maxW = entry.sets.filter { !$0.isWarmup }.map(\.actualLoadKg).max() ?? (draftRows.first?.loadKg ?? 60.0)
            let name = catalog.exercise(id: entry.exerciseID)?.name ?? "Exercise"
            activeSheet = .workingWeight(name: name, id: entry.exerciseID, maxWeight: maxW)
        }

        if runner.currentEntryIndex < runner.entriesInOrder.count - 1 {
            runner.markDone(entryIndex: runner.currentEntryIndex)
            // Land on the exercise list, not straight into the next exercise — the
            // one you just finished now shows green there, and you pick (or
            // substitute) what's next instead of always taking it in plan order.
            onOpenList()
        } else {
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
