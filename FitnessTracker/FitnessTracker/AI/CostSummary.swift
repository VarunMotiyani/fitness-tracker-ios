import Foundation

nonisolated struct CostSummary: Sendable, Equatable {
    struct AICallRecordSnapshot: Sendable, Equatable {
        let timestamp: Date
        let costUSD: Double
    }

    let monthToDateUSD: Double
    let allTimeUSD: Double
    let callCount: Int

    /// Currency formatting normally rounds to cents, which makes legitimate
    /// API usage under one cent look identical to a zero-cost configuration.
    /// Keep normal amounts localized, but preserve enough precision for the
    /// small totals typical of a few test calls.
    var monthToDateDisplay: String {
        Self.display(monthToDateUSD)
    }

    /// Same precision rules as ``monthToDateDisplay`` for the full ledger.
    var allTimeDisplay: String {
        Self.display(allTimeUSD)
    }

    /// Not `private` — `AICallLogView` formats each individual record's
    /// billed cost with the same sub-cent-aware rule rather than a second,
    /// possibly-drifting copy.
    static func display(_ amount: Double) -> String {
        guard amount > 0 else { return "$0.00" }
        if amount < 0.01 {
            let precise = String(format: "$%.4f", amount)
            return precise == "$0.0000" ? "<$0.0001" : precise
        }
        return amount.formatted(.currency(code: "USD"))
    }

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
