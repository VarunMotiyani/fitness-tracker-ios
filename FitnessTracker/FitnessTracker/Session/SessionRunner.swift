import Foundation
import SwiftData
import Metrics
import FitnessDomain
import ExerciseCatalog

/// The four per-set flags a logger can toggle. All default `false`.
struct SetFlags: Sendable {
    var isWarmup = false
    var isDropSet = false
    var toFailure = false
    var assisted = false
    init() {}
}

/// Owns the live-session lifecycle state machine. Every mutation persists
/// immediately via `modelContext.save()`. `finish` (and the static
/// `resolveAbandoned` sweep) run PR detection against the persisted
/// `PersonalRecordModel` table.
///
/// Ruling 5: SwiftData does not guarantee relationship-array order, so every
/// `entryIndex` is resolved against `orderedEntries` (entries sorted by
/// `performedOrder`), and a set list is read sorted by `startedAt`.
@MainActor
@Observable
final class SessionRunner {

    enum Phase: Equatable {
        case idle
        case finalizing
        case active
        case summary
        case finished(SessionOutcome)
    }

    private(set) var phase: Phase = .idle
    private(set) var session: CompletedSessionModel?
    private(set) var finalized: FinalizedSession?
    private(set) var lastSessionPRs: [PersonalRecord] = []

    /// Drives the Focus view. Free to set to any valid index (jump-around).
    var currentEntryIndex: Int = 0

    private let modelContext: ModelContext
    private let catalog: CatalogStore
    private let repository: any MetricsRepository
    private let finalizer: SessionFinalizer
    private let now: () -> Date

    /// The outcome computed by `finish`, replayed by `closeSummary`.
    private var resolvedOutcome: SessionOutcome = .partial

    init(modelContext: ModelContext,
         catalog: CatalogStore,
         repository: any MetricsRepository,
         finalizer: SessionFinalizer,
         now: @escaping () -> Date = { .now }) {
        self.modelContext = modelContext
        self.catalog = catalog
        self.repository = repository
        self.finalizer = finalizer
        self.now = now
    }

    // MARK: - Ordering

    /// Entries in `performedOrder` order (Ruling 5). Use everywhere an
    /// `entryIndex` is resolved.
    private var orderedEntries: [CompletedEntryModel] {
        session?.entries.sorted { $0.performedOrder < $1.performedOrder } ?? []
    }

    // MARK: - View-support accessors

    /// Entries in the order the runner treats as canonical (by `performedOrder`).
    var entriesInOrder: [CompletedEntryModel] { orderedEntries }

    /// The entry the Focus view is currently on, if the index is valid.
    var currentEntry: CompletedEntryModel? {
        let e = orderedEntries
        return e.indices.contains(currentEntryIndex) ? e[currentEntryIndex] : nil
    }

    // MARK: - Lifecycle

    func start(planned: PlannedSession, energy: EnergyRating, timeAvailableMin: Int) {
        guard phase == .idle else { return }   // F4: no second CompletedSessionModel on a double-tap
        phase = .finalizing

        let fin = finalizer.finalize(planned, energy: energy, timeAvailableMin: timeAvailableMin)
        self.finalized = fin

        let ts = now()
        let cal = Calendar.isoUTC
        let weekdayRaw = cal.component(.weekday, from: ts)
        let timeOfDayMinutes = cal.component(.hour, from: ts) * 60 + cal.component(.minute, from: ts)

        let estMinutes = fin.session.items.reduce(0.0) {
            $0 + Double($1.targetSets) * (40 + Double($1.restSeconds))
        } / 60
        let plannedDurationMin = Int(estMinutes.rounded())

        let it = CompletedSessionModel(
            startedAt: ts,
            weekdayRaw: weekdayRaw,
            timeOfDayMinutes: timeOfDayMinutes,
            plannedDurationMin: plannedDurationMin,
            energyRaw: energy.rawValue,
            timeAvailableMin: timeAvailableMin,
            plannedSessionID: planned.id
        )
        modelContext.insert(it)

        for (idx, item) in fin.session.items.enumerated() {
            let entry = CompletedEntryModel(exerciseID: item.exerciseID, performedOrder: idx)
            it.entries.append(entry)
        }
        try? modelContext.save()

        self.session = it
        currentEntryIndex = 0
        phase = .active
    }

    func logSet(entryIndex: Int,
                actualReps: Int,
                actualLoadKg: Double,
                restBeforeSec: Int,
                flags: SetFlags = .init()) {
        let entries = orderedEntries
        guard entries.indices.contains(entryIndex) else { return }
        let entry = entries[entryIndex]

        // Resolve the finalized item by `exerciseID`, not by index: `entryIndex`
        // indexes the `performedOrder`-sorted view, which `reorder` can diverge
        // from `finalized.session.items` (fixed finalisation order). Fall back to
        // `actualReps` / nil load when the item can't be matched.
        let plannedItem = finalized?.session.items.first { $0.exerciseID == entry.exerciseID }
        let targetReps = plannedItem?.targetReps.min ?? actualReps
        let targetLoadKg = plannedItem?.targetLoadKg

        let ts = now()
        let set = LoggedSetModel(
            targetReps: targetReps,
            targetLoadKg: targetLoadKg,
            actualReps: actualReps,
            actualLoadKg: actualLoadKg,
            startedAt: ts,
            completedAt: ts,
            restBeforeSec: restBeforeSec
        )
        set.isWarmup = flags.isWarmup
        set.isDropSet = flags.isDropSet
        set.toFailure = flags.toFailure
        set.assisted = flags.assisted

        entry.sets.append(set)
        entry.stateRaw = EntryState.inProgress.rawValue
        try? modelContext.save()
    }

    func markDone(entryIndex: Int) {
        let entries = orderedEntries
        guard entries.indices.contains(entryIndex) else { return }
        entries[entryIndex].stateRaw = EntryState.done.rawValue
        try? modelContext.save()
    }

    func markSkipped(entryIndex: Int) {
        let entries = orderedEntries
        guard entries.indices.contains(entryIndex) else { return }
        entries[entryIndex].stateRaw = EntryState.done.rawValue
        entries[entryIndex].skipped = true
        try? modelContext.save()
    }

    func reorder(from: Int, to: Int) {
        var entries = orderedEntries
        guard entries.indices.contains(from), entries.indices.contains(to) else { return }
        let moved = entries.remove(at: from)
        entries.insert(moved, at: to)
        for (idx, entry) in entries.enumerated() {
            entry.performedOrder = idx
        }
        try? modelContext.save()
    }

    func setFeel(entryIndex: Int, _ feel: Feel) {
        let entries = orderedEntries
        guard entries.indices.contains(entryIndex) else { return }
        entries[entryIndex].feelRaw = feel.rawValue
        try? modelContext.save()
    }

    func setEntryNote(entryIndex: Int, _ text: String) {
        let entries = orderedEntries
        guard entries.indices.contains(entryIndex) else { return }
        entries[entryIndex].note = text
        try? modelContext.save()
    }

    func finish(partialReason: PartialReason?, overallNote: String?) {
        guard let session, session.finishedAt == nil else { return }   // F4: idempotent

        // F1/F3: compute the outcome from the CURRENT entry states, BEFORE the
        // promotion loop below — a genuinely partial session (unfinished, or
        // every entry skipped) must not be flipped to `.complete`. A skipped
        // entry never counts as "done".
        let outcome: SessionOutcome = orderedEntries.allSatisfy {
            $0.stateRaw == EntryState.done.rawValue && !$0.skipped
        } ? .complete : .partial

        // F1: promote entries the user logged real working sets on but never
        // ticked "Done", so their volume and PRs count (Phase 2a gates metrics
        // on `!skipped && state == .done`).
        Self.promoteWorkedEntries(of: session)

        let ts = now()
        session.finishedAt = ts
        session.actualDurationMin = Int((ts.timeIntervalSince(session.startedAt) / 60).rounded())
        session.outcomeRaw = outcome.rawValue
        session.partialReasonRaw = partialReason?.rawValue
        session.overallNote = overallNote
        try? modelContext.save()

        let new = Self.detectAndPersistPRs(for: session, in: modelContext)
        lastSessionPRs = new
        resolvedOutcome = outcome
        phase = .summary
    }

    func closeSummary() {
        phase = .finished(resolvedOutcome)
    }

    /// Move from active logging to the summary screen WITHOUT persisting the
    /// outcome yet — the summary collects the partial reason / notes, then
    /// calls `finish`.
    func requestSummary() {
        guard phase == .active else { return }
        phase = .summary
    }

    // MARK: - Abandoned-session sweep

    /// Called once from `RootView.task`. Any session left unfinished for longer
    /// than `staleAfter` is closed as `.partial`, dated back to its start, and
    /// run through the same PR detection.
    static func resolveAbandoned(in context: ModelContext,
                                 now: Date,
                                 staleAfter: TimeInterval = 4 * 3600) {
        let all = (try? context.fetch(FetchDescriptor<CompletedSessionModel>())) ?? []
        for session in all where session.finishedAt == nil {
            guard now.timeIntervalSince(session.startedAt) > staleAfter else { continue }
            // Dated back to its start so a long-stale session doesn't distort
            // the current week — passing `now: startedAt` yields
            // `finishedAt == startedAt` and `actualDurationMin == 0`.
            closeSessionAsPartial(session, in: context, now: session.startedAt)
        }
        try? context.save()
    }

    /// F7: close a single in-progress session as `.partial` — promote its
    /// worked-but-not-ticked entries (F1) so their volume/PRs count, stamp
    /// `finishedAt`/`actualDurationMin`, clear any partial reason, and run PR
    /// detection. Shared by the 4h `resolveAbandoned` sweep and
    /// `SessionContainerView`'s orphan sweep when the user re-enters a planned
    /// session that was never finished.
    // TODO(2d): offer to resume the in-progress session instead of auto-closing it as partial
    static func closeSessionAsPartial(_ session: CompletedSessionModel,
                                      in context: ModelContext,
                                      now: Date) {
        guard session.finishedAt == nil else { return }
        promoteWorkedEntries(of: session)
        session.finishedAt = now
        session.outcomeRaw = SessionOutcome.partial.rawValue
        session.partialReasonRaw = nil
        session.actualDurationMin = Int((now.timeIntervalSince(session.startedAt) / 60).rounded())
        try? context.save()
        _ = detectAndPersistPRs(for: session, in: context)
    }

    /// F1: promote any entry the user logged real working sets on (non-warmup,
    /// `actualReps > 0`) but never ticked "Done" to `.done`, so Phase 2a's
    /// `countsTowardMetrics` (`!skipped && state == .done`) lets its volume and
    /// PRs through. Skipped and warmup-/zero-rep-only entries are left alone.
    static func promoteWorkedEntries(of session: CompletedSessionModel) {
        for e in session.entries where !e.skipped
            && e.stateRaw == EntryState.inProgress.rawValue
            && e.sets.contains(where: { !$0.isWarmup && $0.actualReps > 0 }) {
            e.stateRaw = EntryState.done.rawValue
        }
    }

    // MARK: - PR detection

    @discardableResult
    private static func detectAndPersistPRs(for session: CompletedSessionModel,
                                            in context: ModelContext) -> [PersonalRecord] {
        let snapshot = session.toSnapshot()
        let prior = (try? context.fetch(FetchDescriptor<PersonalRecordModel>()))?
            .map { $0.toSnapshot() } ?? []
        let new = PRDetector.newPRs(in: snapshot, priorPRs: prior)
        for pr in new {
            context.insert(personalRecordModel(from: pr))
        }
        try? context.save()
        return new
    }
}
