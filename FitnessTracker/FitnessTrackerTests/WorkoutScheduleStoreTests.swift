import Foundation
import Testing
import SwiftData
import FitnessDomain
import RuleEngine
@testable import FitnessTracker

@Suite(.serialized)
@MainActor
struct WorkoutScheduleStoreTests {
    /// Save/restore every UserDefaults key the store touches so tests don't
    /// leak into each other or into the rest of the suite.
    private func withCleanStore(_ body: () throws -> Void) rethrows {
        let d = UserDefaults.standard
        let keys = [WorkoutScheduleStore.scheduleKey, WorkoutScheduleStore.dayPlanKey, WorkoutScheduleStore.autoPlanKey]
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
