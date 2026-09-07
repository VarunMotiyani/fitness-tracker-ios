import Foundation
import FitnessDomain
import Metrics

public enum SetRowKind: String, Sendable, Codable {
    case straight, dropset, restpause
}

public enum SetRowOps {
    public static func addDrop(to set: LoggedSetSnapshot, loadKg: Double, reps: Int) -> LoggedSetSnapshot {
        var drops = set.drops
        drops.append(DropSetEntry(loadKg: loadKg, reps: reps))
        return LoggedSetSnapshot(
            targetReps: set.targetReps,
            targetLoadKg: set.targetLoadKg,
            actualReps: set.actualReps,
            actualLoadKg: set.actualLoadKg,
            startedAt: set.startedAt,
            completedAt: set.completedAt,
            restBeforeSec: set.restBeforeSec,
            rpe: set.rpe,
            isWarmup: set.isWarmup,
            isDropSet: true,
            toFailure: set.toFailure,
            assisted: set.assisted,
            drops: drops,
            clusters: set.clusters,
            heldSec: set.heldSec,
            rir: set.rir
        )
    }

    public static func addCluster(to set: LoggedSetSnapshot, reps: Int, restSec: Int) -> LoggedSetSnapshot {
        var clusters = set.clusters
        clusters.append(RestPauseCluster(reps: reps, restSeconds: restSec))
        return LoggedSetSnapshot(
            targetReps: set.targetReps,
            targetLoadKg: set.targetLoadKg,
            actualReps: set.actualReps,
            actualLoadKg: set.actualLoadKg,
            startedAt: set.startedAt,
            completedAt: set.completedAt,
            restBeforeSec: set.restBeforeSec,
            rpe: set.rpe,
            isWarmup: set.isWarmup,
            isDropSet: set.isDropSet,
            toFailure: set.toFailure,
            assisted: set.assisted,
            drops: set.drops,
            clusters: clusters,
            heldSec: set.heldSec,
            rir: set.rir
        )
    }

    public static func removeDrop(from set: LoggedSetSnapshot, at i: Int) -> LoggedSetSnapshot {
        var drops = set.drops
        if i >= 0 && i < drops.count {
            drops.remove(at: i)
        }
        return LoggedSetSnapshot(
            targetReps: set.targetReps,
            targetLoadKg: set.targetLoadKg,
            actualReps: set.actualReps,
            actualLoadKg: set.actualLoadKg,
            startedAt: set.startedAt,
            completedAt: set.completedAt,
            restBeforeSec: set.restBeforeSec,
            rpe: set.rpe,
            isWarmup: set.isWarmup,
            isDropSet: !drops.isEmpty,
            toFailure: set.toFailure,
            assisted: set.assisted,
            drops: drops,
            clusters: set.clusters,
            heldSec: set.heldSec,
            rir: set.rir
        )
    }

    public static func removeCluster(from set: LoggedSetSnapshot, at i: Int) -> LoggedSetSnapshot {
        var clusters = set.clusters
        if i >= 0 && i < clusters.count {
            clusters.remove(at: i)
        }
        return LoggedSetSnapshot(
            targetReps: set.targetReps,
            targetLoadKg: set.targetLoadKg,
            actualReps: set.actualReps,
            actualLoadKg: set.actualLoadKg,
            startedAt: set.startedAt,
            completedAt: set.completedAt,
            restBeforeSec: set.restBeforeSec,
            rpe: set.rpe,
            isWarmup: set.isWarmup,
            isDropSet: set.isDropSet,
            toFailure: set.toFailure,
            assisted: set.assisted,
            drops: set.drops,
            clusters: clusters,
            heldSec: set.heldSec,
            rir: set.rir
        )
    }

    public static func setDrop(_ set: LoggedSetSnapshot, at i: Int, loadKg: Double?, reps: Int?) -> LoggedSetSnapshot {
        var drops = set.drops
        guard i >= 0 && i < drops.count else { return set }
        let current = drops[i]
        drops[i] = DropSetEntry(loadKg: loadKg ?? current.loadKg, reps: reps ?? current.reps)
        return LoggedSetSnapshot(
            targetReps: set.targetReps,
            targetLoadKg: set.targetLoadKg,
            actualReps: set.actualReps,
            actualLoadKg: set.actualLoadKg,
            startedAt: set.startedAt,
            completedAt: set.completedAt,
            restBeforeSec: set.restBeforeSec,
            rpe: set.rpe,
            isWarmup: set.isWarmup,
            isDropSet: true,
            toFailure: set.toFailure,
            assisted: set.assisted,
            drops: drops,
            clusters: set.clusters,
            heldSec: set.heldSec,
            rir: set.rir
        )
    }

    public static func setCluster(_ set: LoggedSetSnapshot, at i: Int, reps: Int?, restSec: Int?) -> LoggedSetSnapshot {
        var clusters = set.clusters
        guard i >= 0 && i < clusters.count else { return set }
        let current = clusters[i]
        return LoggedSetSnapshot(
            targetReps: set.targetReps,
            targetLoadKg: set.targetLoadKg,
            actualReps: set.actualReps,
            actualLoadKg: set.actualLoadKg,
            startedAt: set.startedAt,
            completedAt: set.completedAt,
            restBeforeSec: set.restBeforeSec,
            rpe: set.rpe,
            isWarmup: set.isWarmup,
            isDropSet: set.isDropSet,
            toFailure: set.toFailure,
            assisted: set.assisted,
            drops: set.drops,
            clusters: clusters,
            heldSec: set.heldSec,
            rir: set.rir
        )
    }

    public static func nextDropLoad(previousKg: Double, pct: Double = 20) -> Double {
        let raw = previousKg * (1.0 - pct / 100.0)
        return (raw * 2.0).rounded() / 2.0
    }

    public static func nextBurstReps(previous: Int) -> Int {
        max(1, Int((Double(previous) / 2.0).rounded()))
    }

    public static func splitBurstReps(total: Int) -> [Int] {
        guard total > 0 else { return [] }
        var remaining = total
        var bursts: [Int] = []
        var current = max(1, Int((Double(total) / 2.0).rounded()))
        while remaining > 0 {
            let val = min(remaining, current)
            bursts.append(val)
            remaining -= val
            current = max(1, Int((Double(val) / 2.0).rounded()))
        }
        return bursts
    }

    public static func extraVolume(_ set: LoggedSetSnapshot) -> Double {
        set.drops.reduce(0.0) { $0 + ($1.loadKg * Double($1.reps)) }
    }
}
