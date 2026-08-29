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

    private func finalizer() -> SessionFinalizer {
        SessionFinalizer(catalog: catalog(), repository: emptyRepo())
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

    @Test func startCreatesActiveSessionWithTwoNotStartedEntries() throws {
        let (runner, ctx) = try makeRunner()
        runner.start(planned: plannedSession(), energy: .normal, timeAvailableMin: 999)

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

    @Test func logSetAppendsSetsAndMarksInProgress() throws {
        let (runner, _) = try makeRunner()
        runner.start(planned: plannedSession(), energy: .normal, timeAvailableMin: 999)

        runner.logSet(entryIndex: 0, actualReps: 8, actualLoadKg: 60, restBeforeSec: 90)
        runner.logSet(entryIndex: 0, actualReps: 7, actualLoadKg: 60, restBeforeSec: 120)

        let entry = runner.session!.entries.first { $0.performedOrder == 0 }!
        #expect(entry.sets.count == 2)
        #expect(entry.stateRaw == EntryState.inProgress.rawValue)
    }

    @Test func finishWithAllEntriesDoneIsComplete() throws {
        var t = Date(timeIntervalSince1970: 1_000_000)
        let (runner, _) = try makeRunner(now: { t })
        runner.start(planned: plannedSession(), energy: .normal, timeAvailableMin: 999)

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

    @Test func finishWithIncompleteEntriesIsPartial() throws {
        let (runner, _) = try makeRunner()
        runner.start(planned: plannedSession(), energy: .normal, timeAvailableMin: 999)

        runner.markDone(entryIndex: 0) // entry 1 left notStarted

        runner.finish(partialReason: .ranOutOfTime, overallNote: nil)

        #expect(runner.session?.outcomeRaw == SessionOutcome.partial.rawValue)
        #expect(runner.session?.partialReasonRaw == PartialReason.ranOutOfTime.rawValue)

        runner.closeSummary()
        #expect(runner.phase == .finished(.partial))
    }

    @Test func heaviestLoadSetProducesPersonalRecord() throws {
        let (runner, ctx) = try makeRunner()
        runner.start(planned: plannedSession(), energy: .normal, timeAvailableMin: 999)

        runner.logSet(entryIndex: 0, actualReps: 5, actualLoadKg: 100, restBeforeSec: 90)
        runner.markDone(entryIndex: 0)
        runner.markDone(entryIndex: 1)
        runner.finish(partialReason: nil, overallNote: nil)

        let prs = try ctx.fetch(FetchDescriptor<PersonalRecordModel>())
        #expect(!prs.isEmpty)
        #expect(!runner.lastSessionPRs.isEmpty)
        #expect(prs.contains { $0.exerciseID == "bench" && $0.typeRaw == PRType.heaviestWeight.rawValue && $0.value == 100 })
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
