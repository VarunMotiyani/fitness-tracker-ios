import Testing
import Foundation
@testable import Metrics

@Suite struct WeekKeyTests {
    @Test func sundayAndMondayWeekKeysDifferForSundaySession() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        
        // 2026-09-06 is Sunday, 2026-09-12 is Saturday
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 9
        comps.day = 6
        let sunday = cal.date(from: comps)!

        comps.day = 12
        let saturday = cal.date(from: comps)!

        let sunKeySun = WeekKey.key(sunday, weekStart: .sunday, calendar: cal)
        let satKeySun = WeekKey.key(saturday, weekStart: .sunday, calendar: cal)
        #expect(sunKeySun == satKeySun) // Same week under Sunday start

        let sunKeyMon = WeekKey.key(sunday, weekStart: .monday, calendar: cal)
        let satKeyMon = WeekKey.key(saturday, weekStart: .monday, calendar: cal)
        #expect(sunKeyMon != satKeyMon) // Different weeks under Monday start (Sunday was tail of previous week)
    }
}
