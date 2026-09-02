import Testing
import Foundation
@testable import Metrics
@testable import FitnessDomain

@Suite("StreakCalculatorTests")
struct StreakCalculatorTests {

    private func makeSession(daysAgo: Int, calendar: Calendar = .isoUTC) -> CompletedSessionSnapshot {
        let now = Date()
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        let entry = CompletedEntrySnapshot(
            exerciseID: "bench_press",
            performedOrder: 0,
            sets: [
                LoggedSetSnapshot(targetReps: 8, targetLoadKg: 80, actualReps: 8, actualLoadKg: 80,
                                  startedAt: date, completedAt: date, restBeforeSec: 90, rpe: nil,
                                  isWarmup: false, isDropSet: false, toFailure: false, assisted: false)
            ],
            feel: .good,
            note: nil,
            skipped: false
        )
        return CompletedSessionSnapshot(
            id: UUID(),
            date: date,
            weekdayRaw: calendar.component(.weekday, from: date),
            timeOfDayMinutes: 600,
            plannedDurationMin: 60,
            actualDurationMin: 55,
            energy: .normal,
            timeAvailableMin: 60,
            outcome: .complete,
            partialReason: nil,
            overallNote: nil,
            entries: [entry]
        )
    }

    @Test("Empty sessions produce zero streak")
    func emptyStreak() {
        let summary = StreakCalculator.computeSummary(from: [], plannedPerWeek: 4)
        #expect(summary.currentStreakWeeks == 0)
        #expect(summary.workoutsThisWeek == 0)
        #expect(summary.totalWorkouts == 0)
    }

    @Test("Session today produces 1 week streak and 1 workout this week")
    func todaySessionStreak() {
        let s = makeSession(daysAgo: 0)
        let summary = StreakCalculator.computeSummary(from: [s], plannedPerWeek: 4)
        #expect(summary.currentStreakWeeks == 1)
        #expect(summary.workoutsThisWeek == 1)
        #expect(summary.totalWorkouts == 1)
    }

    @Test("Sessions across 3 consecutive weeks produce 3 week streak")
    func threeConsecutiveWeeks() {
        let s1 = makeSession(daysAgo: 0)
        let s2 = makeSession(daysAgo: 7)
        let s3 = makeSession(daysAgo: 14)
        let summary = StreakCalculator.computeSummary(from: [s1, s2, s3], plannedPerWeek: 4)
        #expect(summary.currentStreakWeeks == 3)
        #expect(summary.totalWorkouts == 3)
    }

    @Test("Gap in training breaks the streak")
    func gapBreaksStreak() {
        let s1 = makeSession(daysAgo: 0)
        let s2 = makeSession(daysAgo: 21) // skipped 2 weeks
        let summary = StreakCalculator.computeSummary(from: [s1, s2], plannedPerWeek: 4)
        #expect(summary.currentStreakWeeks == 1)
        #expect(summary.totalWorkouts == 2)
    }
}
