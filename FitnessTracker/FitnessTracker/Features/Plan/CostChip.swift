import SwiftUI

/// Small capsule showing month-to-date AI spend, for the plan screen toolbar.
struct CostChip: View {
    let summary: CostSummary

    var body: some View {
        Text("\(summary.monthToDateDisplay) this month")
            .font(.caption)
            .monospacedDigit()
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }
}
