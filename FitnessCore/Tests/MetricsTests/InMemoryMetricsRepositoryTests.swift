import Testing
import Foundation
import FitnessDomain
import ExerciseCatalog
@testable import Metrics

@Suite struct InMemoryMetricsRepositoryTests {

    // MARK: - Fixture

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        return calendar.date(from: c)!
    }

    private func exercise(_ id: String, _ primary: MuscleGroup) -> Exercise {
        Exercise(id: id, name: id, primaryMuscle: primary, secondaryMuscles: [],
                 equipment: .barbell, mechanic: .compound, force: .push,
                 difficulty: .intermediate, isUnilateral: false, instructions: [], imagePaths: [])
    }

    private func catalog() -> CatalogStore {
        CatalogStore(exercises: [exercise("bench", .chest), exercise("squat", .quads)])
    }

    private func set(_ reps: Int, _ load: Double, warmup: Bool = false) -> LoggedSetSnapshot {
        LoggedSetSnapshot(targetReps: reps, targetLoadKg: load, actualReps: reps, actualLoadKg: load,
            startedAt: .init(timeIntervalSince1970: 0), completedAt: .init(timeIntervalSince1970: 30),
            restBeforeSec: 90, rpe: nil, isWarmup: warmup, isDropSet: false, toFailure: false, assisted: false)
    }

    private func session(_ d: Date, _ entries: [(ex: String, feel: Feel, sets: [LoggedSetSnapshot])],
                         outcome: SessionOutcome = .complete) -> CompletedSessionSnapshot {
        let completed = entries.enumerated().map { (i, e) in
            CompletedEntrySnapshot(exerciseID: e.ex, performedOrder: i, state: .done, skipped: false,
                wasSwappedFrom: nil, feel: e.feel, note: nil, sets: e.sets)
        }
        return CompletedSessionSnapshot(id: UUID(), date: d, weekday: 3, timeOfDayMinutes: 600,
            plannedDurationMin: 60, actualDurationMin: 60, energy: .normal, timeAvailableMin: 60,
            outcome: outcome, partialReason: outcome == .partial ? .ranOutOfTime : nil,
            coachSource: .rule, plannedSessionID: nil, entries: completed, overallNote: nil)
    }

    private var s1Date: Date { date(2026, 1, 5) }   // week 1
    private var s2Date: Date { date(2026, 1, 12) }  // week 2
    private var s3Date: Date { date(2026, 1, 19) }  // week 3 (Mon)
    private var s4Date: Date { date(2026, 1, 21) }  // week 3 (Wed) — same ISO week as s3
    private var now: Date { date(2026, 1, 28) }

    private var observations: [ObservationSnapshot] {
        [
            ObservationSnapshot(kind: "bodyweight", value: 80.0, unit: "kg", timestamp: date(2026, 1, 6),
                                context: [:], sessionID: nil, entryExerciseID: nil),
            ObservationSnapshot(kind: "bodyweight", value: 79.2, unit: "kg", timestamp: date(2026, 1, 20),
                                context: [:], sessionID: nil, entryExerciseID: nil),
            ObservationSnapshot(kind: "sleepQuality", value: 7, unit: "score", timestamp: date(2026, 1, 10),
                                context: [:], sessionID: nil, entryExerciseID: nil),
        ]
    }

    private var plannedSessionsPerWeek: Int { 3 }

    private func repo() -> InMemoryMetricsRepository {
        // bench: 4 sessions. Heaviest-Epley set (8 reps @ 100) is in s1, so the last 3
        // trend points are flat -> bench is a stall.
        // squat: 3 sessions with rising e1RM -> NOT a stall.
        let sessions = [
            session(s1Date, [
                ("bench", .easy, [set(5, 100), set(8, 100)]),
                ("squat", .right, [set(5, 100)]),
            ]),
            session(s2Date, [
                ("bench", .right, [set(5, 100)]),
                ("squat", .right, [set(5, 110)]),
            ]),
            session(s3Date, [
                ("bench", .brutal, [set(5, 100), set(5, 90)]),
                ("squat", .right, [set(5, 120)]),
            ], outcome: .partial),
            session(s4Date, [
                ("bench", .right, [set(5, 100)]),
            ]),
        ]
        return InMemoryMetricsRepository(
            sessions: sessions,
            priorPRs: [],
            observations: observations,
            plannedSessionsPerWeek: plannedSessionsPerWeek,
            catalog: catalog(),
            calendar: calendar)
    }

    // MARK: - Tests

    @Test func lastPerformanceReturnsMostRecentBenchSetsAndFeel() {
        let perf = repo().lastPerformance(exerciseID: "bench")
        #expect(perf?.exerciseID == "bench")
        #expect(perf?.date == s4Date)
        #expect(perf?.sets.count == 1)
        #expect(perf?.sets.first?.actualReps == 5)
        #expect(perf?.sets.first?.actualLoadKg == 100)
        #expect(perf?.feel == .right)
    }

    @Test func lastPerformanceConcatenatesRepeatedEntriesInASession() {
        // bench entered twice in the most recent session (superset re-entry).
        let sessions = [
            session(s1Date, [("bench", .right, [set(5, 100)])]),
            session(s2Date, [
                ("bench", .easy, [set(5, 100), set(5, 100)]),
                ("squat", .right, [set(5, 120)]),
                ("bench", .right, [set(3, 110)]),
            ]),
        ]
        let repo = InMemoryMetricsRepository(
            sessions: sessions, priorPRs: [], observations: [],
            plannedSessionsPerWeek: 3, catalog: catalog(), calendar: calendar)
        let perf = repo.lastPerformance(exerciseID: "bench")
        #expect(perf?.date == s2Date)
        #expect(perf?.sets.count == 3)                 // 2 + 1 across both entries
        #expect(perf?.sets.map(\.actualReps) == [5, 5, 3])
        #expect(perf?.feel == .easy)                   // first matching entry's feel
    }

    @Test func bestSetIsHighestEpleySet() {
        let best = repo().bestSet(exerciseID: "bench", since: nil)
        #expect(best?.actualReps == 8)
        #expect(best?.actualLoadKg == 100)
    }

    @Test func e1RMSeriesHasOnePointPerBenchSessionAscending() {
        let series = repo().e1RMSeries(exerciseID: "bench", since: nil)
        #expect(series.count == 4)
        #expect(series.map(\.date) == series.map(\.date).sorted())
        #expect(series.map(\.date) == [s1Date, s2Date, s3Date, s4Date])
    }

    @Test func weeklyVolumeChestIsWithinWindowAndBucketCount() {
        let out = repo().weeklyVolume(muscle: .chest, weeks: 4, now: now)
        #expect(out.count <= 4)
        #expect(out.allSatisfy { $0.muscle == .chest })
        #expect(out.map(\.weekStart).max()! <= now)
        // s3 + s4 share an ISO week -> 3 distinct chest buckets.
        #expect(out.count == 3)
    }

    @Test func personalRecordsForBenchContainsHeaviestWeightPR() {
        let prs = repo().personalRecords(exerciseID: "bench")
        #expect(prs.allSatisfy { $0.exerciseID == "bench" })
        #expect(prs.contains { $0.type == .heaviestWeight && $0.value == 100 })
    }

    @Test func adherenceIsSessionsInWindowOverPlannedSlots() {
        // 3-week window ending 2026-01-28 -> s2, s3, s4 (s1 falls outside).
        let expected = 3.0 / (3.0 * Double(plannedSessionsPerWeek))
        #expect(abs(repo().adherence(weeks: 3, now: now) - expected) < 1e-9)
    }

    @Test func stallsFlagsFlatExerciseNotRisingOne() {
        #expect(repo().stalls() == ["bench"])
    }

    @Test func observationsFilterByKindAndSince() {
        let all = repo().observations(kind: "bodyweight", since: nil)
        #expect(all.count == 2)
        #expect(all.allSatisfy { $0.kind == "bodyweight" })

        let recent = repo().observations(kind: "bodyweight", since: date(2026, 1, 15))
        #expect(recent.count == 1)
        #expect(recent.first?.value == 79.2)
    }
}
