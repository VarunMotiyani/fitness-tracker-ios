import Testing
import Foundation
@testable import RuleEngine

struct SchedulingTests {
    @Test func effectiveRoutineIDUsesWeekdayUnlessOverridden() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        // 2026-09-04 is Friday (weekday 6)
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 9
        comps.day = 4
        let friday = cal.date(from: comps)!

        let week = [6: "upper_body"] // Friday assigned to upper_body
        
        // 1. Normal without dayPlan override
        let r1 = Scheduling.effectiveRoutineID(week: week, dayPlan: [:], date: friday, calendar: cal)
        #expect(r1 == "upper_body")

        // 2. Overridden with "rest"
        let r2 = Scheduling.effectiveRoutineID(week: week, dayPlan: ["2026-09-04": "rest"], date: friday, calendar: cal)
        #expect(r2 == nil)

        // 3. Overridden with different routine
        let r3 = Scheduling.effectiveRoutineID(week: week, dayPlan: ["2026-09-04": "leg_day"], date: friday, calendar: cal)
        #expect(r3 == "leg_day")
    }

    @Test func nextTrainingDaySkipsRestDays() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        // Friday 2026-09-04 (weekday 6) -> Saturday 2026-09-05 (weekday 7)
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 9
        comps.day = 4
        let friday = cal.date(from: comps)!

        // Friday overridden to rest, Saturday assigned to lower_body
        let week = [7: "lower_body"]
        let dayPlan = ["2026-09-04": "rest"]

        let next = Scheduling.nextTrainingDay(week: week, dayPlan: dayPlan, from: friday, calendar: cal)
        #expect(next != nil)
        #expect(next?.routineID == "lower_body")
    }

    @Test func autoReschedulesMissedWeekdayIntoNextOpenDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        // Recurring plan Mon/Tue/Wed/Fri; today is Wednesday, Tuesday trained.
        let monday = date(cal, year: 2026, month: 9, day: 7)
        let thursday = date(cal, year: 2026, month: 9, day: 10)
        let wednesday = date(cal, year: 2026, month: 9, day: 9)

        let week = [2: "push", 3: "pull", 4: "legs", 6: "upper"]
        let completed = Set([Scheduling.isoDateKey(date(cal, year: 2026, month: 9, day: 8), calendar: cal)])
        let result = Scheduling.autoRescheduleMissedSessions(
            week: week, dayPlan: [:], completedDates: completed, through: wednesday, calendar: cal)

        // Monday was missed → vacated and moved to Thursday, the first free day.
        #expect(result.dayPlan[Scheduling.isoDateKey(monday, calendar: cal)] == "rest")
        #expect(result.dayPlan[Scheduling.isoDateKey(thursday, calendar: cal)] == "push")
        #expect(result.unplaced.isEmpty)
    }

    @Test func autoRescheduleFillsEveryMissedSessionAndUsesSunday() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        // 4-day plan Mon/Tue/Wed/Thu, today is Friday, nothing trained.
        let week = [2: "a", 3: "b", 4: "c", 5: "d"]
        let friday = date(cal, year: 2026, month: 9, day: 11)
        let result = Scheduling.autoRescheduleMissedSessions(
            week: week, dayPlan: [:], completedDates: [], through: friday, calendar: cal)

        // Mon–Thu all missed; only Fri, Sat, Sun remain → 3 placed, 1 unplaced.
        #expect(result.dayPlan[Scheduling.isoDateKey(friday, calendar: cal)] == "a")
        #expect(result.dayPlan[Scheduling.isoDateKey(date(cal, year: 2026, month: 9, day: 12), calendar: cal)] == "b")
        #expect(result.dayPlan[Scheduling.isoDateKey(date(cal, year: 2026, month: 9, day: 13), calendar: cal)] == "c") // Sunday
        #expect(result.unplaced.map(\.routineID) == ["d"])
        #expect(result.unplaced.first?.originalDateKey == Scheduling.isoDateKey(date(cal, year: 2026, month: 9, day: 10), calendar: cal))
    }

    @Test func autoRescheduleChasesAMissedCatchUpDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        // Monday's "push" was already moved to Thursday on an earlier run;
        // Thursday then passed untrained. Today is Friday.
        let mondayKey = Scheduling.isoDateKey(date(cal, year: 2026, month: 9, day: 7), calendar: cal)
        let thursdayKey = Scheduling.isoDateKey(date(cal, year: 2026, month: 9, day: 10), calendar: cal)
        let fridayKey = Scheduling.isoDateKey(date(cal, year: 2026, month: 9, day: 11), calendar: cal)
        let result = Scheduling.autoRescheduleMissedSessions(
            week: [2: "push"],
            dayPlan: [mondayKey: "rest", thursdayKey: "push"],
            completedDates: [],
            through: date(cal, year: 2026, month: 9, day: 11),
            calendar: cal)

        // Thursday's catch-up was itself missed → vacated and moved to the next
        // free day, which is today (Friday).
        #expect(result.dayPlan[thursdayKey] == "rest")
        #expect(result.dayPlan[fridayKey] == "push")
        #expect(result.unplaced.isEmpty)
    }

    @Test func autoRescheduleLeavesRestOverridesAndTrainedDaysAlone() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        let mondayKey = Scheduling.isoDateKey(date(cal, year: 2026, month: 9, day: 7), calendar: cal)
        let result = Scheduling.autoRescheduleMissedSessions(
            week: [2: "push"],
            dayPlan: [mondayKey: "rest"],
            completedDates: [],
            through: date(cal, year: 2026, month: 9, day: 13),
            calendar: cal)

        // Monday's session was explicitly rested — nothing is owed, nothing moves.
        #expect(result.dayPlan == [mondayKey: "rest"])
        #expect(result.unplaced.isEmpty)
    }

    @Test func autoRescheduleAvoidsPlacingARoutineNextToTheSameOne() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        // Mon push, Tue pull, Wed push, Fri legs. Monday missed, today Tuesday.
        let week = [2: "push", 3: "pull", 4: "push", 6: "legs"]
        let tuesday = date(cal, year: 2026, month: 9, day: 8)
        let result = Scheduling.autoRescheduleMissedSessions(
            week: week, dayPlan: [:], completedDates: [], through: tuesday, calendar: cal)

        let thu = Scheduling.isoDateKey(date(cal, year: 2026, month: 9, day: 10), calendar: cal)
        let sat = Scheduling.isoDateKey(date(cal, year: 2026, month: 9, day: 12), calendar: cal)
        // Thursday is free but sits next to Wednesday's push, so push is pushed
        // out to Saturday instead.
        #expect(result.dayPlan[thu] == nil)
        #expect(result.dayPlan[sat] == "push")
    }

    private func date(_ calendar: Calendar, year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
