import Testing
import SwiftData
import Foundation
import FitnessDomain
import ExerciseCatalog
import Metrics
@testable import FitnessTracker

/// Parity suite: `SwiftDataMetricsRepository` fetches finished sessions from a
/// SwiftData context and forwards to `InMemoryMetricsRepository`. Every method
/// (except `personalRecords`, which reads its own table) must return exactly what
/// a directly-constructed `InMemoryMetricsRepository` over the equivalent
/// snapshot arrays returns. The one unfinished session must contribute nothing.
@MainActor
@Suite struct SwiftDataMetricsRepositoryTests {

    // MARK: - Calendar / dates

    private static let cal: Calendar = .isoUTC

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        return Self.cal.date(from: c)!
    }

    private var sADate: Date { date(2026, 2, 2) }   // Mon, ISO week A
    private var sBDate: Date { date(2026, 2, 5) }   // Thu, same ISO week A
    private var sCDate: Date { date(2026, 2, 9) }   // Mon, ISO week B
    private var unfinishedDate: Date { date(2026, 2, 12) }
    private var now: Date { date(2026, 2, 20) }

    private let plannedSessionsPerWeek = 3

    // MARK: - Catalog

    private func exercise(_ id: String, _ primary: MuscleGroup) -> Exercise {
        Exercise(id: id, name: id, primaryMuscle: primary, secondaryMuscles: [],
                 equipment: .barbell, mechanic: .compound, force: .push,
                 difficulty: .intermediate, isUnilateral: false, instructions: [], imagePaths: [])
    }

    private func catalog() -> CatalogStore {
        CatalogStore(exercises: [exercise("bench", .chest), exercise("squat", .quads)])
    }

    // MARK: - Model seeding helpers

    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: CompletedSessionModel.self, CompletedEntryModel.self, LoggedSetModel.self,
            PersonalRecordModel.self, ObservationModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func loggedSet(_ reps: Int, _ load: Double, warmup: Bool = false) -> LoggedSetModel {
        let s = LoggedSetModel(targetReps: reps, targetLoadKg: load, actualReps: reps,
            actualLoadKg: load, startedAt: Date(timeIntervalSince1970: 0),
            completedAt: Date(timeIntervalSince1970: 30), restBeforeSec: 90)
        s.isWarmup = warmup
        return s
    }

    private func entry(_ exerciseID: String, order: Int, feel: Feel,
                       sets: [LoggedSetModel]) -> CompletedEntryModel {
        let e = CompletedEntryModel(exerciseID: exerciseID, performedOrder: order)
        e.stateRaw = EntryState.done.rawValue
        e.feelRaw = feel.rawValue
        for s in sets { e.sets.append(s) }
        return e
    }

    private func session(id: UUID, started: Date, finished: Date?,
                         entries: [CompletedEntryModel]) -> CompletedSessionModel {
        let s = CompletedSessionModel(id: id, startedAt: started, weekdayRaw: 2,
            timeOfDayMinutes: 720, plannedDurationMin: 60, energyRaw: EnergyRating.normal.rawValue,
            timeAvailableMin: 60, plannedSessionID: nil)
        s.finishedAt = finished
        s.actualDurationMin = 60
        s.outcomeRaw = SessionOutcome.complete.rawValue
        for e in entries { s.entries.append(e) }
        return s
    }

    /// Seeds a context and returns the SUT plus a parity `InMemoryMetricsRepository`
    /// built from the finished sessions' snapshots.
    private func makeRepos() throws -> (SwiftDataMetricsRepository, InMemoryMetricsRepository) {
        let ctx = ModelContext(try container())

        let sAID = UUID(), sBID = UUID(), sCID = UUID()

        // bench: flat/declining e1RM across 3 finished sessions -> a stall.
        // squat: rising e1RM -> not a stall.
        let sA = session(id: sAID, started: sADate, finished: sADate.addingTimeInterval(3600), entries: [
            entry("bench", order: 0, feel: .right, sets: [loggedSet(5, 100), loggedSet(8, 100), loggedSet(10, 40, warmup: true)]),
            entry("squat", order: 1, feel: .right, sets: [loggedSet(5, 100)]),
        ])
        let sB = session(id: sBID, started: sBDate, finished: sBDate.addingTimeInterval(3600), entries: [
            entry("bench", order: 0, feel: .easy, sets: [loggedSet(5, 100)]),
            entry("squat", order: 1, feel: .right, sets: [loggedSet(5, 110)]),
        ])
        let sC = session(id: sCID, started: sCDate, finished: sCDate.addingTimeInterval(3600), entries: [
            entry("bench", order: 0, feel: .brutal, sets: [loggedSet(5, 100)]),
            entry("squat", order: 1, feel: .right, sets: [loggedSet(5, 120)]),
        ])
        // Unfinished: only session mentioning "ohp"; must be ignored entirely.
        let unfinished = session(id: UUID(), started: unfinishedDate, finished: nil, entries: [
            entry("ohp", order: 0, feel: .right, sets: [loggedSet(5, 60)]),
        ])

        for s in [sA, sB, sC, unfinished] { ctx.insert(s) }

        // Persisted PRs — deliberately NOT values PRDetector would derive, proving
        // `personalRecords` reads this table rather than re-deriving.
        let pr1 = PersonalRecordModel(typeRaw: PRType.heaviestWeight.rawValue, exerciseID: "bench",
            value: 999, atLoadKg: 999, reps: 1, date: sADate, sessionID: sAID)
        let pr2 = PersonalRecordModel(typeRaw: PRType.estimated1RM.rawValue, exerciseID: "squat",
            value: 555, atLoadKg: 500, reps: 3, date: sCDate, sessionID: sCID)
        ctx.insert(pr1)
        ctx.insert(pr2)

        let obs = ObservationModel(kind: "bodyweight", value: 80.5, unit: "kg", timestamp: date(2026, 2, 3))
        ctx.insert(obs)

        try ctx.save()

        let sut = SwiftDataMetricsRepository(
            context: ctx, catalog: catalog(),
            plannedSessionsPerWeek: plannedSessionsPerWeek, calendar: Self.cal)

        let inner = InMemoryMetricsRepository(
            sessions: [sA, sB, sC].map { $0.toSnapshot() },
            priorPRs: [],
            observations: [obs.toSnapshot()],
            plannedSessionsPerWeek: plannedSessionsPerWeek,
            catalog: catalog(),
            calendar: Self.cal)

        return (sut, inner)
    }

    private func sortedPRs(_ prs: [PersonalRecord]) -> [PersonalRecord] {
        prs.sorted { ($0.exerciseID, $0.type.rawValue) < ($1.exerciseID, $1.type.rawValue) }
    }

    // MARK: - Parity tests

    @Test func lastPerformanceParity() throws {
        let (sut, inner) = try makeRepos()
        #expect(sut.lastPerformance(exerciseID: "bench") == inner.lastPerformance(exerciseID: "bench"))
        #expect(sut.lastPerformance(exerciseID: "squat") == inner.lastPerformance(exerciseID: "squat"))
        #expect(sut.lastPerformance(exerciseID: "bench") != nil)
    }

    @Test func bestSetParity() throws {
        let (sut, inner) = try makeRepos()
        #expect(sut.bestSet(exerciseID: "bench", since: nil) == inner.bestSet(exerciseID: "bench", since: nil))
        #expect(sut.bestSet(exerciseID: "squat", since: sBDate) == inner.bestSet(exerciseID: "squat", since: sBDate))
    }

    @Test func e1RMSeriesParity() throws {
        let (sut, inner) = try makeRepos()
        #expect(sut.e1RMSeries(exerciseID: "bench", since: nil) == inner.e1RMSeries(exerciseID: "bench", since: nil))
        #expect(sut.e1RMSeries(exerciseID: "squat", since: sBDate) == inner.e1RMSeries(exerciseID: "squat", since: sBDate))
        #expect(sut.e1RMSeries(exerciseID: "bench", since: nil).count == 3)
    }

    @Test func weeklyVolumeParity() throws {
        let (sut, inner) = try makeRepos()
        #expect(sut.weeklyVolume(muscle: .chest, weeks: 8, now: now) == inner.weeklyVolume(muscle: .chest, weeks: 8, now: now))
        #expect(sut.weeklyVolume(muscle: .quads, weeks: 8, now: now) == inner.weeklyVolume(muscle: .quads, weeks: 8, now: now))
        #expect(!sut.weeklyVolume(muscle: .chest, weeks: 8, now: now).isEmpty)
    }

    @Test func adherenceParity() throws {
        let (sut, inner) = try makeRepos()
        #expect(sut.adherence(weeks: 4, now: now) == inner.adherence(weeks: 4, now: now))
        #expect(sut.adherence(weeks: 2, now: now) == inner.adherence(weeks: 2, now: now))
    }

    @Test func stallsParity() throws {
        let (sut, inner) = try makeRepos()
        #expect(sut.stalls() == inner.stalls())
        #expect(sut.stalls() == ["bench"])
    }

    @Test func observationsParity() throws {
        let (sut, inner) = try makeRepos()
        #expect(sut.observations(kind: "bodyweight", since: nil) == inner.observations(kind: "bodyweight", since: nil))
        #expect(sut.observations(kind: "bodyweight", since: date(2026, 2, 10)) == inner.observations(kind: "bodyweight", since: date(2026, 2, 10)))
        #expect(sut.observations(kind: "bodyweight", since: nil).count == 1)
        #expect(sut.observations(kind: "bodyweight", since: date(2026, 2, 10)).isEmpty)
    }

    // MARK: - personalRecords: persisted rows, not a re-derivation

    @Test func personalRecordsReturnsPersistedRows() throws {
        let (sut, _) = try makeRepos()

        let all = sortedPRs(sut.personalRecords(exerciseID: nil))
        #expect(all.count == 2)
        #expect(all.contains { $0.exerciseID == "bench" && $0.type == .heaviestWeight && $0.value == 999 })
        #expect(all.contains { $0.exerciseID == "squat" && $0.type == .estimated1RM && $0.value == 555 })

        let bench = sut.personalRecords(exerciseID: "bench")
        #expect(bench.count == 1)
        #expect(bench.first?.value == 999)
        #expect(bench.first?.atLoadKg == 999)
    }

    // MARK: - The unfinished session contributes nothing

    @Test func unfinishedSessionIsIgnored() throws {
        let (sut, _) = try makeRepos()
        #expect(sut.lastPerformance(exerciseID: "ohp") == nil)
        #expect(sut.bestSet(exerciseID: "ohp", since: nil) == nil)
        #expect(sut.e1RMSeries(exerciseID: "ohp", since: nil).isEmpty)
        #expect(!sut.stalls().contains("ohp"))
    }
}
