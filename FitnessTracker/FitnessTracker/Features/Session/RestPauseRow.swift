import SwiftUI
import FitnessDomain
import Metrics
import RuleEngine

public struct RestPauseRow: View {
    public let clusters: [RestPauseCluster]
    public let baseReps: Int
    public let onAddCluster: (Int, Int) -> Void
    public let onRemoveCluster: (Int) -> Void

    public init(
        clusters: [RestPauseCluster],
        baseReps: Int,
        onAddCluster: @escaping (Int, Int) -> Void,
        onRemoveCluster: @escaping (Int) -> Void
    ) {
        self.clusters = clusters
        self.baseReps = baseReps
        self.onAddCluster = onAddCluster
        self.onRemoveCluster = onRemoveCluster
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(clusters.enumerated()), id: \.offset) { index, cluster in
                HStack(spacing: 8) {
                    Text("Burst \(index + 1)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(GymTheme.violet)
                        .frame(width: 55, alignment: .leading)

                    Text("\(cluster.reps) reps · \(cluster.restSeconds)s rest")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(GymTheme.label)

                    Spacer()

                    Button {
                        onRemoveCluster(index)
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
                let lastReps = clusters.last?.reps ?? baseReps
                let nextReps = SetRowOps.nextBurstReps(previous: lastReps)
                onAddCluster(nextReps, 15)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Rest-Pause Burst (15s)")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GymTheme.violet)
                .padding(.vertical, 4)
            }
        }
    }
}
