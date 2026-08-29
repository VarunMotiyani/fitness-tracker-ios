import Testing
import Foundation
import FitnessDomain
import ExerciseCatalog
@testable import Metrics

@Suite struct RollupComputerTests {

    // Fixed gregorian calendar so week bucketing is deterministic.
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func catalog() -> CatalogStore {
        CatalogStore(exercises: [exercise("bench", .chest), exercise("squat", .quads)])
    }

    private func exercise(_ id: String, _ primary: MuscleGroup) -> Exercise {
        Exercise(id: id, name: id, primaryMuscle: primary, secondaryMuscles: [],
                 equipment: .barbell, mechanic: .compound, force: .push,
                 difficulty: .intermediate, isUnilateral: false, instructions: [], imagePaths: [])
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        return calendar.date(from: c)!
    }

    private func set(_ reps: Int, _ load: Double, warmup: Bool = false) -> LoggedSetSnapshot {
        LoggedSetSnapshot(targetReps: reps, targetLoadKg: load, actualReps: reps, actualLoadKg: load,
            startedAt: .init(timeIntervalSince1970: 0), completedAt: .init(timeIntervalSince1970: 30),
            restBeforeSec: 90, rpe: nil, isWarmup: warmup, isDropSet: false, toFailure: false, assisted: false)
    }

    private func session(_ d: Date, _ entries: [(ex: String, sets: [LoggedSetSnapshot])],
                         outcome: SessionOutcome = .complete) -> CompletedSessionSnapshot {
        let completed = entries.enumerated().map { (i, e) in
            CompletedEntrySnapshot(exerciseID: e.ex, performedOrder: i, state: .done, skipped: false,
                wasSwappedFrom: nil, feel: .right, note: nil, sets: e.sets)
        }
        return CompletedSessionSnapshot(id: UUID(), date: d, weekday: 3, timeOfDayMinutes: 600,
            plannedDurationMin: 60, actualDurationMin: 60, energy: .normal, timeAvailableMin: 60,
            outcome: outcome, partialReason: outcome == .partial ? .ranOutOfTime : nil,
            coachSource: .rule, plannedSessionID: nil, entries: completed, overallNote: nil)
    }

    // 2026-01-05 (Mon) and 2026-01-07 (Wed) are the same ISO week; 2026-01-14 is the next.
    private var week1a: Date { date(2026, 1, 5) }
    private var week1b: Date { date(2026, 1, 7) }
    private var week2: Date { date(2026, 1, 14) }

    @Test func weeklyMuscleVolumeGroupsWeek1AndIsolatesWeek2() {
        let sessions = [
            session(week1a, [("bench", [set(5, 100), set(5, 100), set(5, 100)]),
                             ("squat", [set(5, 140), set(5, 140)])]),
            session(week1b, [("bench", [set(5, 100), set(5, 100)])]),
            session(week2, [("bench", [set(5, 100)])]),
        ]
        let out = RollupComputer(catalog: catalog()).weeklyMuscleVolume(from: sessions, calendar: calendar)

        let w1Start = calendar.dateInterval(of: .weekOfYear, for: week1a)!.start
        let w2Start = calendar.dateInterval(of: .weekOfYear, for: week2)!.start
        #expect(w1Start != w2Start)

        #expect(out == [
            WeeklyMuscleVolume(weekStart: w1Start, muscle: .chest, sets: 5),
            WeeklyMuscleVolume(weekStart: w1Start, muscle: .quads, sets: 2),
            WeeklyMuscleVolume(weekStart: w2Start, muscle: .chest, sets: 1),
        ])
    }

    @Test func warmupSetIsNotCounted() {
        let sessions = [session(week1a, [("bench", [set(5, 100), set(5, 100), set(3, 60, warmup: true)])])]
        let out = RollupComputer(catalog: catalog()).weeklyMuscleVolume(from: sessions, calendar: calendar)
        #expect(out.map(\.sets) == [2])
        #expect(out.first?.muscle == .chest)
    }

    @Test func partialSessionCountsLikeComplete() {
        let sessions = [session(week1a, [("bench", [set(5, 100)])], outcome: .partial)]
        let out = RollupComputer(catalog: catalog()).weeklyMuscleVolume(from: sessions, calendar: calendar)
        #expect(out.map(\.sets) == [1])
    }

    @Test func unknownExerciseIdInSetIsSkippedWithoutCrash() {
        let sessions = [session(week1a, [("mystery", [set(5, 100), set(5, 100)]),
                                         ("bench", [set(5, 100)])])]
        let out = RollupComputer(catalog: catalog()).weeklyMuscleVolume(from: sessions, calendar: calendar)
        #expect(out == [WeeklyMuscleVolume(weekStart: calendar.dateInterval(of: .weekOfYear, for: week1a)!.start,
                                           muscle: .chest, sets: 1)])
    }

    @Test func exerciseTrendOnePointPerSessionSortedByDate() {
        let sessions = [
            session(week2, [("bench", [set(3, 120)])]),
            session(week1a, [("bench", [set(5, 100), set(5, 90)])]),
        ]
        let out = RollupComputer(catalog: catalog()).exerciseTrend(from: sessions, exerciseID: "bench")
        #expect(out.count == 2)
        #expect(out.map(\.date) == [week1a, week2])

        // First session: best set is (5, 100) by Epley; tonnage = 5*100 + 5*90.
        #expect(out[0].bestSetLoadKg == 100)
        #expect(out[0].bestSetReps == 5)
        #expect(out[0].tonnage == 950)
        #expect(out[0].e1RM == Estimated1RM.epley(loadKg: 100, reps: 5))

        // Heavier session pushes e1RM up (monotone increase here).
        #expect(out[1].e1RM > out[0].e1RM)
        #expect(out[1].e1RM == Estimated1RM.epley(loadKg: 120, reps: 3))
        #expect(out[1].tonnage == 360)
    }

    @Test func skippedZeroRepEntryYieldsNoVolumeOrTrend() {
        let ghost = LoggedSetSnapshot(targetReps: 5, targetLoadKg: 100, actualReps: 0, actualLoadKg: 100,
            startedAt: .init(timeIntervalSince1970: 0), completedAt: .init(timeIntervalSince1970: 0),
            restBeforeSec: 0, rpe: nil, isWarmup: false, isDropSet: false, toFailure: false, assisted: false)
        let entry = CompletedEntrySnapshot(exerciseID: "bench", performedOrder: 0, state: .done,
            skipped: true, wasSwappedFrom: nil, feel: nil, note: nil, sets: [ghost])
        let s = CompletedSessionSnapshot(id: UUID(), date: week1a, weekday: 3, timeOfDayMinutes: 600,
            plannedDurationMin: 60, actualDurationMin: 60, energy: .normal, timeAvailableMin: 60,
            outcome: .complete, partialReason: nil, coachSource: .rule, plannedSessionID: nil,
            entries: [entry], overallNote: nil)
        let rollup = RollupComputer(catalog: catalog())
        #expect(rollup.weeklyMuscleVolume(from: [s], calendar: calendar).isEmpty)
        #expect(rollup.exerciseTrend(from: [s], exerciseID: "bench").isEmpty)
    }

    @Test func exerciseTrendIgnoresWarmupsAndOtherExercises() {
        let sessions = [
            session(week1a, [("squat", [set(5, 140)]),
                             ("bench", [set(1, 200, warmup: true)])]),
            session(week1b, [("bench", [set(5, 100)])]),
        ]
        let out = RollupComputer(catalog: catalog()).exerciseTrend(from: sessions, exerciseID: "bench")
        #expect(out.count == 1)
        #expect(out[0].date == week1b)
        #expect(out[0].bestSetLoadKg == 100)
    }
}
