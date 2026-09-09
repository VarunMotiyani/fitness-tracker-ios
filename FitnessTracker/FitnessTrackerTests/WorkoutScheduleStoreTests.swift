import Foundation
import Testing
import SwiftData
import FitnessDomain
import ExerciseCatalog
import RuleEngine
@testable import FitnessTracker

@Suite(.serialized)
@MainActor
struct WorkoutScheduleStoreTests {
    /// Save/restore every UserDefaults key the store touches so tests don't
    /// leak into each other or into the rest of the suite.
    private func withCleanStore(_ body: () throws -> Void) rethrows {
        let d = UserDefaults.standard
        let keys = [WorkoutScheduleStore.scheduleKey, WorkoutScheduleStore.dayPlanKey,
                    WorkoutScheduleStore.autoPlanKey, WorkoutScheduleStore.dayWorkoutOverrideKey]
        let saved = keys.map { d.string(forKey: $0) }
        for k in keys { d.removeObject(forKey: k) }
        defer { for (k, v) in zip(keys, saved) { d.set(v, forKey: k) } }
        try body()
    }

    private func container() throws -> ModelContainer {
        try ModelContainer(for: CompletedSessionModel.self, CompletedEntryModel.self, LoggedSetModel.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        WorkoutScheduleStore.calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    // MARK: - Date-scoped workout overrides (Task 1)

    private func pushPlan() -> WeeklyPlan {
        WeeklyPlan(weekStartDate: date(2026, 9, 7), source: .ruleEngine, rationale: "test",
                   sessions: [PlannedSession(id: UUID(), order: 0, focusMuscles: [.chest, .shoulders, .triceps],
                       items: [
                           PlannedItem(exerciseID: "bench", targetSets: 3, targetReps: RepRange(min: 6, max: 8), targetLoadKg: 60, restSeconds: 120, coachNote: ""),
                           PlannedItem(exerciseID: "triceps_pressdown", targetSets: 3, targetReps: RepRange(min: 10, max: 12), targetLoadKg: nil, restSeconds: 90, coachNote: "")
                       ])], weeklyVolumeTargets: [])
    }

    private func schedule(_ plan: WeeklyPlan, on date: Date) {
        WorkoutScheduleStore.saveDayPlan([
            Scheduling.isoDateKey(date, calendar: WorkoutScheduleStore.calendar): plan.sessions[0].id.uuidString
        ])
    }

    private func exercise(_ id: String, primary: MuscleGroup) -> Exercise {
        Exercise(id: id, name: id, primaryMuscle: primary, secondaryMuscles: [],
                 equipment: .machine, mechanic: .compound, force: .push,
                 difficulty: .intermediate, isUnilateral: false, instructions: [], imagePaths: [])
    }

    private func pushCatalog(including extraIDs: [String] = []) -> CatalogStore {
        var exercises = [
            exercise("bench", primary: .chest),
            exercise("machine_press", primary: .chest),
            exercise("triceps_pressdown", primary: .triceps)
        ]
        if extraIDs.contains("row") { exercises.append(exercise("row", primary: .back)) }
        return CatalogStore(exercises: exercises)
    }

    @Test func dateOverrideReplacesAnExerciseWithoutMutatingWeeklyPlan() {
        withCleanStore {
            let date = date(2026, 9, 9)
            let plan = pushPlan()
            let catalog = pushCatalog()
            schedule(plan, on: date)

            #expect(WorkoutScheduleStore.replaceExercise(
                "bench", with: catalog.exercise(id: "machine_press")!,
                on: date, in: plan, catalog: catalog, origin: .manual))

            let effective = WorkoutScheduleStore.effectiveSession(for: date, in: plan)!
            #expect(effective.items.map(\.exerciseID) == ["machine_press", "triceps_pressdown"])
            #expect(plan.sessions[0].items.map(\.exerciseID) == ["bench", "triceps_pressdown"])
        }
    }

    @Test func incompatibleOrDuplicateExerciseIsRejected() {
        withCleanStore {
            let date = date(2026, 9, 9)
            let plan = pushPlan()
            let catalog = pushCatalog(including: ["row"])
            schedule(plan, on: date)

            #expect(!WorkoutScheduleStore.addExercise(catalog.exercise(id: "row")!, on: date, in: plan, catalog: catalog, origin: .manual))
            #expect(!WorkoutScheduleStore.addExercise(catalog.exercise(id: "bench")!, on: date, in: plan, catalog: catalog, origin: .manual))
        }
    }

    @Test func staleBaseSessionOverrideIsIgnored() {
        withCleanStore {
            let date = date(2026, 9, 9)
            let plan = pushPlan()
            schedule(plan, on: date)
            WorkoutScheduleStore.saveDayWorkoutOverride(.init(
                dateKey: Scheduling.isoDateKey(date, calendar: WorkoutScheduleStore.calendar),
                baseSessionID: UUID(), focusMuscles: [.chest], items: [], origin: .manual, updatedAt: date))

            #expect(WorkoutScheduleStore.effectiveSession(for: date, in: plan)?.items.map(\.exerciseID) == ["bench", "triceps_pressdown"])
        }
    }

    @Test func addAndRemoveRoundTripAndRemoveKeepsAtLeastOne() {
        withCleanStore {
            let d = date(2026, 9, 9)
            let plan = pushPlan()
            let catalog = pushCatalog()
            schedule(plan, on: d)

            #expect(WorkoutScheduleStore.addExercise(catalog.exercise(id: "machine_press")!, on: d, in: plan, catalog: catalog, origin: .manual))
            #expect(WorkoutScheduleStore.effectiveSession(for: d, in: plan)!.items.map(\.exerciseID) == ["bench", "triceps_pressdown", "machine_press"])

            #expect(WorkoutScheduleStore.removeExercise("bench", on: d, in: plan))
            #expect(WorkoutScheduleStore.effectiveSession(for: d, in: plan)!.items.map(\.exerciseID) == ["triceps_pressdown", "machine_press"])

            #expect(WorkoutScheduleStore.removeExercise("triceps_pressdown", on: d, in: plan))
            // One item left — the store refuses to empty the session.
            #expect(!WorkoutScheduleStore.removeExercise("machine_press", on: d, in: plan))
            #expect(WorkoutScheduleStore.effectiveSession(for: d, in: plan)!.items.map(\.exerciseID) == ["machine_press"])
        }
    }

    @Test func resetDropsTheOverrideAndRestoresTheScheduledSession() {
        withCleanStore {
            let d = date(2026, 9, 9)
            let plan = pushPlan()
            let catalog = pushCatalog()
            schedule(plan, on: d)
            _ = WorkoutScheduleStore.replaceExercise("bench", with: catalog.exercise(id: "machine_press")!,
                                                     on: d, in: plan, catalog: catalog, origin: .manual)

            WorkoutScheduleStore.removeDayWorkoutOverride(for: d)

            #expect(WorkoutScheduleStore.dayWorkoutOverride(for: d, in: plan) == nil)
            #expect(WorkoutScheduleStore.effectiveSession(for: d, in: plan)!.items.map(\.exerciseID) == ["bench", "triceps_pressdown"])
        }
    }

    @Test func convertsMondayFirstScheduleToEffectiveRoutine() {
        withCleanStore {
            let routine = UUID()
            WorkoutScheduleStore.saveWeekSchedule([0: routine])
            let monday = date(2026, 9, 7)
            #expect(WorkoutScheduleStore.mondayFirstIndex(for: monday) == 0)
            #expect(WorkoutScheduleStore.effectiveRoutineID(for: monday) == routine)
            #expect(!WorkoutScheduleStore.isRescheduled(for: monday))
        }
    }

    @Test func explicitRestOverrideWinsAndIsNotRescheduled() {
        withCleanStore {
            WorkoutScheduleStore.saveWeekSchedule([0: UUID()])
            let d = date(2026, 9, 7)
            WorkoutScheduleStore.saveDayPlan([Scheduling.isoDateKey(d, calendar: WorkoutScheduleStore.calendar): "rest"])
            #expect(WorkoutScheduleStore.effectiveRoutineID(for: d) == nil)
            #expect(!WorkoutScheduleStore.isRescheduled(for: d))
        }
    }

    /// The bug behind "4-day plan shows 5 days": a session finished on its
    /// original day used to leave a stale catch-up on the day it had been moved
    /// to. `refresh` must recompute the auto layer from scratch each call.
    @Test func completingAMissedSessionDropsItsStaleCatchUp() throws {
        try withCleanStore {
            let ctx = ModelContext(try container())
            let push = UUID(), pull = UUID(), legs = UUID(), lower = UUID()
            // Mon/Tue/Wed/Thu recurring plan.
            WorkoutScheduleStore.saveWeekSchedule([0: push, 1: pull, 2: legs, 3: lower])

            // Wednesday: Monday and Tuesday were both missed → two catch-ups.
            _ = WorkoutScheduleStore.refresh(completedSessions: [], now: date(2026, 9, 9))
            let afterMiss = WorkoutScheduleStore.autoDayPlan.values.filter { $0.lowercased() != "rest" }.count
            #expect(afterMiss == 2)

            // Now Monday's session actually gets completed (logged on Monday).
            let done = CompletedSessionModel(startedAt: date(2026, 9, 7), weekdayRaw: 2, timeOfDayMinutes: 540,
                                             plannedDurationMin: 60, energyRaw: "normal", timeAvailableMin: 60,
                                             plannedSessionID: nil)
            done.finishedAt = date(2026, 9, 7)
            ctx.insert(done)

            _ = WorkoutScheduleStore.refresh(completedSessions: [done], now: date(2026, 9, 9))
            let afterComplete = WorkoutScheduleStore.autoDayPlan.values.filter { $0.lowercased() != "rest" }.count
            // Only Tuesday's catch-up should remain — Monday's is gone.
            #expect(afterComplete == 1)
        }
    }

    @Test func autoLayerNeverLeaksIntoTheUserPlan() throws {
        try withCleanStore {
            WorkoutScheduleStore.saveWeekSchedule([0: UUID(), 1: UUID()])
            _ = WorkoutScheduleStore.refresh(completedSessions: [], now: date(2026, 9, 9))
            // User plan stays empty; auto layer holds the reschedule.
            #expect(WorkoutScheduleStore.userDayPlan.isEmpty)
            #expect(!WorkoutScheduleStore.autoDayPlan.isEmpty)
        }
    }
}
