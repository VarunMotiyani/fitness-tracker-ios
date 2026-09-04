import Testing
import SwiftData
import Foundation
import FitnessDomain
import ExerciseCatalog
import Metrics
@testable import FitnessTracker

/// Drives the `SessionRunner` state machine: `start` finalises + persists a
/// `CompletedSessionModel`, `logSet`/`markDone`/`markSkipped` mutate + persist,
/// `finish` computes the outcome and runs PR detection, and `resolveAbandoned`
/// closes stale unfinished sessions. In-memory container over all 12 model types.
@MainActor
@Suite struct SessionRunnerTests {

    // MARK: - Fixtures

    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: UserProfile.self, StoredPlan.self, ProviderProfile.self, AICallRecord.self,
            CompletedSessionModel.self, CompletedEntryModel.self, LoggedSetModel.self,
            BodyweightEntryModel.self, DailyCheckinModel.self, ObservationModel.self,
            PersonalRecordModel.self, CoachMemoryModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func exercise(_ id: String) -> Exercise {
        Exercise(id: id, name: id, primaryMuscle: .chest, secondaryMuscles: [],
                 equipment: .barbell, mechanic: .compound, force: .push,
                 difficulty: .intermediate, isUnilateral: false, instructions: [], imagePaths: [])
    }

    private func catalog() -> CatalogStore {
        CatalogStore(exercises: [exercise("bench"), exercise("row")])
    }

    private func emptyRepo() -> InMemoryMetricsRepository {
        InMemoryMetricsRepository(sessions: [], priorPRs: [], observations: [],
                                  plannedSessionsPerWeek: 3, catalog: catalog())
    }

    private func finalizer() -> RuleEngineFinalizer {
        RuleEngineFinalizer(catalog: catalog(), repository: emptyRepo())
    }

    private func plannedSession() -> PlannedSession {
        PlannedSession(id: UUID(), order: 0, focusMuscles: [.chest], items: [
            PlannedItem(exerciseID: "bench", targetSets: 3, targetReps: RepRange(min: 6, max: 8),
                        targetLoadKg: 60, restSeconds: 90, coachNote: ""),
            PlannedItem(exerciseID: "row", targetSets: 3, targetReps: RepRange(min: 8, max: 10),
                        targetLoadKg: 50, restSeconds: 90, coachNote: ""),
        ])
    }

    private func makeRunner(now: @escaping () -> Date = { .now }) throws -> (SessionRunner, ModelContext) {
        let ctx = ModelContext(try container())
        let runner = SessionRunner(modelContext: ctx, catalog: catalog(),
                                   repository: emptyRepo(), finalizer: finalizer(), now: now)
        return (runner, ctx)
    }

    // MARK: - Scenarios

    @Test func startCreatesActiveSessionWithTwoNotStartedEntries() async throws {
        let (runner, ctx) = try makeRunner()
        await runner.start(planned: plannedSession(), energy: .normal, timeAvailableMin: 999)

        #expect(runner.phase == .active)
        #expect(runner.finalized != nil)
        #expect(runner.session != nil)

        let sessions = try ctx.fetch(FetchDescriptor<CompletedSessionModel>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.finishedAt == nil)
        #expect(sessions.first?.entries.count == 2)
        #expect(sessions.first?.entries.allSatisfy { $0.stateRaw == EntryState.notStarted.rawValue } == true)
        #expect(sessions.first?.plannedSessionID != nil)
    }

    @Test func logSetAppendsSetsAndMarksInProgress() async throws {
        let (runner, _) = try makeRunner()
        await runner.start(planned: plannedSession(), energy: .normal, timeAvailableMin: 999)

        runner.logSet(entryIndex: 0, actualReps: 8, actualLoadKg: 60, restBeforeSec: 90)
        runner.logSet(entryIndex: 0, actualReps: 7, actualLoadKg: 60, restBeforeSec: 120)

        let entry = runner.session!.entries.first { $0.performedOrder == 0 }!
        #expect(entry.sets.count == 2)
        #expect(entry.stateRaw == EntryState.inProgress.rawValue)
    }

    @Test func finishWithAllEntriesDoneIsComplete() async throws {
        var t = Date(timeIntervalSince1970: 1_000_000)
        let (runner, _) = try makeRunner(now: { t })
        await runner.start(planned: plannedSession(), energy: .normal, timeAvailableMin: 999)

        runner.logSet(entryIndex: 0, actualReps: 8, actualLoadKg: 60, restBeforeSec: 90)
        runner.markDone(entryIndex: 0)
        runner.markDone(entryIndex: 1)

        t = t.addingTimeInterval(3600)
        runner.finish(partialReason: nil, overallNote: "good work")

        #expect(runner.phase == .summary)
        #expect(runner.session?.outcomeRaw == SessionOutcome.complete.rawValue)
        #expect(runner.session?.finishedAt != nil)
        #expect((runner.session?.actualDurationMin ?? -1) >= 0)
        #expect(runner.session?.overallNote == "good work")

        runner.closeSummary()
        #expect(runner.phase == .finished(.complete))
    }

    @Test func finishWithIncompleteEntriesIsPartial() async throws {
        let (runner, _) = try makeRunner()
        await runner.start(planned: plannedSession(), energy: .normal, timeAvailableMin: 999)

        runner.markDone(entryIndex: 0) // entry 1 left notStarted

        runner.finish(partialReason: .ranOutOfTime, overallNote: nil)

        #expect(runner.session?.outcomeRaw == SessionOutcome.partial.rawValue)
        #expect(runner.session?.partialReasonRaw == PartialReason.ranOutOfTime.rawValue)

        runner.closeSummary()
        #expect(runner.phase == .finished(.partial))
    }

    @Test func heaviestLoadSetProducesPersonalRecord() async throws {
        let (runner, ctx) = try makeRunner()
        await runner.start(planned: plannedSession(), energy: .normal, timeAvailableMin: 999)

        runner.logSet(entryIndex: 0, actualReps: 5, actualLoadKg: 100, restBeforeSec: 90)
        runner.markDone(entryIndex: 0)
        runner.markDone(entryIndex: 1)
        runner.finish(partialReason: nil, overallNote: nil)

        let prs = try ctx.fetch(FetchDescriptor<PersonalRecordModel>())
        #expect(!prs.isEmpty)
        #expect(!runner.lastSessionPRs.isEmpty)
        #expect(prs.contains { $0.exerciseID == "bench" && $0.typeRaw == PRType.heaviestWeight.rawValue && $0.value == 100 })
    }

    @Test func logSetAfterReorderTakesTargetsFromTheReorderedExercise() async throws {
        let (runner, ctx) = try makeRunner()
        await runner.start(planned: plannedSession(), energy: .normal, timeAvailableMin: 999)

        // bench (entry 0, load 60) and row (entry 1, load 50) with distinct
        // finalized targets, read back so the assertion doesn't assume progression held.
        let benchTarget = runner.finalized!.session.items.first { $0.exerciseID == "bench" }!.targetLoadKg
        let rowTarget = runner.finalized!.session.items.first { $0.exerciseID == "row" }!.targetLoadKg
        #expect(benchTarget != rowTarget)

        // Move bench to the back: row is now entry 0.
        runner.reorder(from: 0, to: 1)
        #expect(runner.session?.entries.first { $0.performedOrder == 0 }?.exerciseID == "row")

        runner.logSet(entryIndex: 0, actualReps: 9, actualLoadKg: 55, restBeforeSec: 90)

        let rowEntry = runner.session!.entries.first { $0.exerciseID == "row" }!
        #expect(rowEntry.sets.count == 1)
        #expect(rowEntry.sets.first?.targetLoadKg == rowTarget)
        #expect(rowEntry.sets.first?.targetLoadKg != benchTarget)

        // Nothing was written onto bench.
        let benchEntry = runner.session!.entries.first { $0.exerciseID == "bench" }!
        #expect(benchEntry.sets.isEmpty)
        _ = ctx
    }

    @Test func resolveAbandonedClosesStaleUnfinishedSession() throws {
        let ctx = ModelContext(try container())
        let started = Date(timeIntervalSince1970: 1_000_000)
        let stale = CompletedSessionModel(
            id: UUID(), startedAt: started, weekdayRaw: 2, timeOfDayMinutes: 600,
            plannedDurationMin: 60, energyRaw: EnergyRating.normal.rawValue,
            timeAvailableMin: 60, plannedSessionID: nil)
        ctx.insert(stale)
        try ctx.save()

        SessionRunner.resolveAbandoned(in: ctx, now: started.addingTimeInterval(5 * 3600))

        let sessions = try ctx.fetch(FetchDescriptor<CompletedSessionModel>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.finishedAt == started)
        #expect(sessions.first?.outcomeRaw == SessionOutcome.partial.rawValue)
        #expect(sessions.first?.partialReasonRaw == nil)
        #expect(sessions.first?.actualDurationMin == 0)
    }

    // MARK: - Fix wave

    /// F1: sets logged on an entry the user never ticked "Done" must still feed
    /// PRs and volume — `finish` promotes the entry — while the overall outcome
    /// stays `.partial` because another entry was never touched.
    @Test func finishPromotesWorkedButNotDoneEntries() async throws {
        var t = Date(timeIntervalSince1970: 1_000_000)
        let (runner, ctx) = try makeRunner(now: { t })
        await runner.start(planned: plannedSession(), energy: .normal, timeAvailableMin: 999)

        runner.logSet(entryIndex: 0, actualReps: 5, actualLoadKg: 100, restBeforeSec: 90)
        runner.logSet(entryIndex: 0, actualReps: 5, actualLoadKg: 100, restBeforeSec: 90)
        runner.logSet(entryIndex: 0, actualReps: 5, actualLoadKg: 100, restBeforeSec: 90)
        // deliberately no markDone; entry 1 never touched

        t = t.addingTimeInterval(1800)
        runner.finish(partialReason: .ranOutOfTime, overallNote: nil)

        #expect(runner.session?.outcomeRaw == SessionOutcome.partial.rawValue)
        #expect(runner.session?.partialReasonRaw == PartialReason.ranOutOfTime.rawValue)

        let entry0 = runner.entriesInOrder[0]
        #expect(entry0.stateRaw == EntryState.done.rawValue)
        #expect(entry0.skipped == false)

        let prs = try ctx.fetch(FetchDescriptor<PersonalRecordModel>())
        #expect(prs.contains { $0.exerciseID == "bench" })
        #expect(!runner.lastSessionPRs.isEmpty)

        let rollup = RollupComputer(catalog: catalog())
            .weeklyMuscleVolume(from: [runner.session!.toSnapshot()], calendar: .isoUTC)
        #expect(rollup.contains { $0.muscle == .chest && $0.sets >= 3 })
    }

    /// F3: every entry skipped is a `.partial` session, not `.complete`.
    @Test func finishWithAllEntriesSkippedIsPartial() async throws {
        let (runner, _) = try makeRunner()
        await runner.start(planned: plannedSession(), energy: .normal, timeAvailableMin: 999)

        runner.markSkipped(entryIndex: 0)
        runner.markSkipped(entryIndex: 1)
        runner.finish(partialReason: .notFeelingIt, overallNote: nil)

        #expect(runner.session?.outcomeRaw == SessionOutcome.partial.rawValue)
        runner.closeSummary()
        #expect(runner.phase == .finished(.partial))
    }

    /// F4: a second `finish` is a no-op — one PR row per PR, note / PR reveal intact.
    @Test func finishIsIdempotent() async throws {
        var t = Date(timeIntervalSince1970: 1_000_000)
        let (runner, ctx) = try makeRunner(now: { t })
        await runner.start(planned: plannedSession(), energy: .normal, timeAvailableMin: 999)

        runner.logSet(entryIndex: 0, actualReps: 5, actualLoadKg: 100, restBeforeSec: 90)
        runner.markDone(entryIndex: 0)
        runner.markDone(entryIndex: 1)

        t = t.addingTimeInterval(3600)
        runner.finish(partialReason: nil, overallNote: "first note")

        let prCount = try ctx.fetch(FetchDescriptor<PersonalRecordModel>()).count
        let prsShown = runner.lastSessionPRs
        let finishedAt = runner.session?.finishedAt
        #expect(!prsShown.isEmpty)

        t = t.addingTimeInterval(99_999)
        runner.finish(partialReason: .tooTired, overallNote: "second note")

        #expect(try ctx.fetch(FetchDescriptor<PersonalRecordModel>()).count == prCount)
        #expect(runner.session?.overallNote == "first note")
        #expect(runner.session?.partialReasonRaw == nil)
        #expect(runner.session?.finishedAt == finishedAt)
        #expect(runner.lastSessionPRs.count == prsShown.count)
    }

    /// F7: an orphan in-progress session for a planned slot is closed as
    /// `.partial` with full volume/PR credit, and a fresh `start` for the same
    /// slot creates a distinct session.
    @Test func closeSessionAsPartialClosesOrphanAndStartMakesDistinctSession() async throws {
        let ctx = ModelContext(try container())
        let planned = plannedSession()
        let started = Date(timeIntervalSince1970: 1_000_000)

        let orphan = CompletedSessionModel(
            id: UUID(), startedAt: started, weekdayRaw: 2, timeOfDayMinutes: 600,
            plannedDurationMin: 60, energyRaw: EnergyRating.normal.rawValue,
            timeAvailableMin: 60, plannedSessionID: planned.id)
        ctx.insert(orphan)
        let entry = CompletedEntryModel(exerciseID: "bench", performedOrder: 0)
        orphan.entries.append(entry)
        entry.stateRaw = EntryState.inProgress.rawValue
        for _ in 0..<2 {
            entry.sets.append(LoggedSetModel(
                targetReps: 5, targetLoadKg: 100, actualReps: 5, actualLoadKg: 120,
                startedAt: started, completedAt: started, restBeforeSec: 90))
        }
        try ctx.save()

        let now = started.addingTimeInterval(1200)
        SessionRunner.closeSessionAsPartial(orphan, in: ctx, now: now)

        #expect(orphan.finishedAt == now)
        #expect(orphan.outcomeRaw == SessionOutcome.partial.rawValue)
        #expect(orphan.entries.first?.stateRaw == EntryState.done.rawValue)
        #expect(try ctx.fetch(FetchDescriptor<PersonalRecordModel>()).contains { $0.exerciseID == "bench" })

        let runner = SessionRunner(modelContext: ctx, catalog: catalog(),
                                   repository: emptyRepo(), finalizer: finalizer(), now: { now })
        await runner.start(planned: planned, energy: .normal, timeAvailableMin: 999)
        #expect(runner.session?.id != orphan.id)

        let unfinished = try ctx.fetch(FetchDescriptor<CompletedSessionModel>())
            .filter { $0.finishedAt == nil }
        #expect(unfinished.count == 1)
        #expect(unfinished.first?.id == runner.session?.id)
    }

    @Test func resolveAbandonedLeavesFreshUnfinishedSessionAlone() throws {
        let ctx = ModelContext(try container())
        let started = Date(timeIntervalSince1970: 1_000_000)
        let fresh = CompletedSessionModel(
            id: UUID(), startedAt: started, weekdayRaw: 2, timeOfDayMinutes: 600,
            plannedDurationMin: 60, energyRaw: EnergyRating.normal.rawValue,
            timeAvailableMin: 60, plannedSessionID: nil)
        ctx.insert(fresh)
        try ctx.save()

        SessionRunner.resolveAbandoned(in: ctx, now: started.addingTimeInterval(3600))

        let sessions = try ctx.fetch(FetchDescriptor<CompletedSessionModel>())
        #expect(sessions.first?.finishedAt == nil)
        #expect(sessions.first?.outcomeRaw == nil)
    }
}
