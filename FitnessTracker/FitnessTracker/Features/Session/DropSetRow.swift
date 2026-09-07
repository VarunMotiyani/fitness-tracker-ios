import SwiftUI
import FitnessDomain
import Metrics
import RuleEngine

public struct DropSetRow: View {
    public let drops: [DropSetEntry]
    public let baseLoadKg: Double
    public let onAddDrop: (Double, Int) -> Void
    public let onRemoveDrop: (Int) -> Void
    public let onUpdateDrop: (Int, Double?, Int?) -> Void

    public init(
        drops: [DropSetEntry],
        baseLoadKg: Double,
        onAddDrop: @escaping (Double, Int) -> Void,
        onRemoveDrop: @escaping (Int) -> Void,
        onUpdateDrop: @escaping (Int, Double?, Int?) -> Void
    ) {
        self.drops = drops
        self.baseLoadKg = baseLoadKg
        self.onAddDrop = onAddDrop
        self.onRemoveDrop = onRemoveDrop
        self.onUpdateDrop = onUpdateDrop
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(drops.enumerated()), id: \.offset) { index, drop in
                HStack(spacing: 8) {
                    Text("Drop \(index + 1)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(GymTheme.orange)
                        .frame(width: 50, alignment: .leading)

                    Text("\(String(format: "%.1f", drop.loadKg)) kg × \(drop.reps) reps")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(GymTheme.label)

                    Spacer()

                    Button {
                        onRemoveDrop(index)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(GymTheme.red.opacity(0.8))
                            .padding(6)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 8))
            }

            Button {
                let lastLoad = drops.last?.loadKg ?? baseLoadKg
                let nextLoad = SetRowOps.nextDropLoad(previousKg: lastLoad, pct: 20)
                onAddDrop(nextLoad, 8)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Drop Set (−20%)")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GymTheme.orange)
                .padding(.vertical, 4)
            }
        }
    }
}
