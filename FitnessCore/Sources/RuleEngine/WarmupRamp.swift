import Foundation
import Metrics

public enum WarmupRamp {
    /// Recompute the warm-up block so it ramps toward the weight the work rows ACTUALLY carry.
    /// Done rows and work rows are untouched. Snapped to `step`.
    public static func reramp(rows: [LoggedSetSnapshot], step: Double = 2.5) -> [LoggedSetSnapshot] {
        guard let firstWork = rows.firstIndex(where: { !$0.isWarmup }), firstWork > 0 else {
            return rows
        }
        let target = rows[firstWork].targetLoadKg ?? rows[firstWork].actualLoadKg
        guard target > 0 else { return rows }

        var out = rows
        var from: Double = 0.0

        for i in 0..<firstWork {
            let s = out[i]
            let isDone = s.actualReps > 0
            if isDone {
                from = s.actualLoadKg
                continue
            }
            let w: Double
            if target > from {
                let mid = from + (target - from) / 2.0
                let snapped = floor(mid / step) * step
                w = max(0.0, min(target, snapped))
            } else {
                w = target
            }
            out[i] = LoggedSetSnapshot(
                targetReps: s.targetReps,
                targetLoadKg: w,
                actualReps: s.actualReps,
                actualLoadKg: w,
                startedAt: s.startedAt,
                completedAt: s.completedAt,
                restBeforeSec: s.restBeforeSec,
                rpe: s.rpe,
                isWarmup: s.isWarmup,
                isDropSet: s.isDropSet,
                toFailure: s.toFailure,
                assisted: s.assisted,
                drops: s.drops,
                clusters: s.clusters
            )
            from = w
        }
        return out
    }

    /// Cascade a weight change forward: following sets of the same warm-up flag that are still
    /// undone take the new value. Done sets and sets with mismatched warmup status are never rewritten.
    public static func cascadeWeight(rows: [LoggedSetSnapshot], from index: Int, value: Double?) -> [LoggedSetSnapshot] {
        guard index >= 0 && index < rows.count else { return rows }
        let warm = rows[index].isWarmup
        var next = rows
        for j in (index + 1)..<next.count {
            let s = next[j]
            let isDone = s.actualReps > 0
            if s.isWarmup == warm && !isDone {
                let newLoad = value ?? 0.0
                next[j] = LoggedSetSnapshot(
                    targetReps: s.targetReps,
                    targetLoadKg: value,
                    actualReps: s.actualReps,
                    actualLoadKg: newLoad,
                    startedAt: s.startedAt,
                    completedAt: s.completedAt,
                    restBeforeSec: s.restBeforeSec,
                    rpe: s.rpe,
                    isWarmup: s.isWarmup,
                    isDropSet: s.isDropSet,
                    toFailure: s.toFailure,
                    assisted: s.assisted,
                    drops: s.drops,
                    clusters: s.clusters
                )
            }
        }
        return next
    }
}
