import Testing
import Foundation
@testable import FitnessTracker

struct CostSummaryTests {
    @Test func splitsMonthToDateFromAllTime() {
        let cal = Calendar.current
        let now = Date()
        let thisMonth = now
        let lastMonth = cal.date(byAdding: .month, value: -1, to: now)!

        let snaps = [
            CostSummary.AICallRecordSnapshot(timestamp: thisMonth, costUSD: 0.10),
            CostSummary.AICallRecordSnapshot(timestamp: thisMonth, costUSD: 0.05),
            CostSummary.AICallRecordSnapshot(timestamp: lastMonth, costUSD: 1.00),
        ]
        let s = CostSummary.from(records: snaps, now: now)
        #expect(abs(s.monthToDateUSD - 0.15) < 1e-9)
        #expect(abs(s.allTimeUSD - 1.15) < 1e-9)
        #expect(s.callCount == 3)
    }
}
