import Foundation
import FitnessDomain
import ExerciseCatalog
import RuleEngine
import Metrics

/// The output of `SessionFinalizer.finalize`: the rebuilt session plus a
/// per-exercise rationale string from the progression rule.
nonisolated struct FinalizedSession: Sendable {
    let session: PlannedSession
    let perItemRationale: [String: String]

    init(session: PlannedSession, perItemRationale: [String: String]) {
        self.session = session
        self.perItemRationale = perItemRationale
    }
}

/// Deterministic rule-engine session finalisation (spec §5.4): progression per
/// exercise, then an energy trim, then a time trim. No AI, no network. This is
/// the seam Phase 2c later swaps the AI `finalize` call into.
@MainActor
struct SessionFinalizer {
    private let catalog: CatalogStore
    private let repository: any MetricsRepository

    init(catalog: CatalogStore, repository: any MetricsRepository) {
        self.catalog = catalog
        self.repository = repository
    }

    func finalize(_ planned: PlannedSession,
                  energy: EnergyRating,
                  timeAvailableMin: Int) -> FinalizedSession {

        // Step 1 — progression per item, preserving `planned.items` order.
        var perItemRationale: [String: String] = [:]
        var items: [PlannedItem] = planned.items.map { item in
            let mechanic = catalog.exercise(id: item.exerciseID)?.mechanic ?? .unknown
            let lastPerf = repository.lastPerformance(exerciseID: item.exerciseID)
            let decision = ProgressionRule().next(
                currentTargetLoadKg: item.targetLoadKg ?? 0,
                currentTargetSets: item.targetSets,
                repRange: item.targetReps,
                mechanic: mechanic,
                lastPerformance: lastPerf
            )
            // Keep `nil` only when the decision load is 0 AND there was no history
            // — don't write a literal 0.
            let newLoad: Double? = (decision.targetLoadKg == 0 && lastPerf == nil)
                ? nil
                : decision.targetLoadKg
            perItemRationale[item.exerciseID] = decision.rationale
            return PlannedItem(
                exerciseID: item.exerciseID,
                targetSets: decision.targetSets,
                targetReps: item.targetReps,
                targetLoadKg: newLoad,
                restSeconds: item.restSeconds,
                coachNote: item.coachNote
            )
        }

        // Step 2 — energy adjustment. `.beat` drops the last isolation item (less
        // capacity today). `.great` adds one set to the first compound item (extra
        // capacity, spent where it counts most) — `.normal` is the baseline both
        // sides adjust from, so it alone makes no change.
        switch energy {
        case .beat:
            if let idx = items.lastIndex(where: {
                (catalog.exercise(id: $0.exerciseID)?.mechanic ?? .unknown) == .isolation
            }) {
                items.remove(at: idx)
            }
        case .great:
            if let idx = items.firstIndex(where: {
                (catalog.exercise(id: $0.exerciseID)?.mechanic ?? .unknown) == .compound
            }) {
                let item = items[idx]
                items[idx] = PlannedItem(
                    exerciseID: item.exerciseID,
                    targetSets: item.targetSets + 1,
                    targetReps: item.targetReps,
                    targetLoadKg: item.targetLoadKg,
                    restSeconds: item.restSeconds,
                    coachNote: item.coachNote
                )
            }
        case .normal:
            break
        }

        // Step 3 — time trim: drop trailing items until the estimate fits.
        func estimatedMinutes(_ list: [PlannedItem]) -> Double {
            list.reduce(0) { $0 + Double($1.targetSets) * (40 + Double($1.restSeconds)) } / 60
        }
        var estMin = estimatedMinutes(items)
        while estMin > Double(timeAvailableMin) && items.count > 1 {
            items.removeLast()
            estMin = estimatedMinutes(items)
        }

        // Step 4 — rebuild the session (same id / order / focusMuscles).
        let session = PlannedSession(
            id: planned.id,
            order: planned.order,
            focusMuscles: planned.focusMuscles,
            items: items
        )
        return FinalizedSession(session: session, perItemRationale: perItemRationale)
    }
}
