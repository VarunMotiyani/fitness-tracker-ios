import Foundation

nonisolated struct CostSummary: Sendable, Equatable {
    struct AICallRecordSnapshot: Sendable, Equatable {
        let timestamp: Date
        let costUSD: Double
    }

    let monthToDateUSD: Double
    let allTimeUSD: Double
    let callCount: Int

    static func from(records: [AICallRecordSnapshot], now: Date) -> CostSummary {
        let cal = Calendar.current
        let nowComps = cal.dateComponents([.year, .month], from: now)
        var mtd = 0.0
        var all = 0.0
        for r in records {
            all += r.costUSD
            let c = cal.dateComponents([.year, .month], from: r.timestamp)
            if c.year == nowComps.year && c.month == nowComps.month { mtd += r.costUSD }
        }
        return CostSummary(monthToDateUSD: mtd, allTimeUSD: all, callCount: records.count)
    }
}
