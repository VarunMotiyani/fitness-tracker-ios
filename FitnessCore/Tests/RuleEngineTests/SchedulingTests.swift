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
}
