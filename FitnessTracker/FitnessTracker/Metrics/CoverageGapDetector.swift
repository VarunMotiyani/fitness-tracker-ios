import Foundation
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics

/// Deterministic (no LLM call) — proposes adding one exercise for each muscle
/// `MuscleBalanceModel.rankOf` reports as missed this week (design spec §6).
/// Skips a muscle that already has an unresolved pending suggestion for it.
@MainActor
enum CoverageGapDetector {
    static func detect(context: ModelContext, catalog: CatalogStore, storedPlan: StoredPlan) {
        guard let plan = try? storedPlan.decodedPlan(), let firstSession = plan.sessions.first else { return }

        var effectiveSetItems: [MuscleBalanceModel.EffectiveSetItem] = []
        for session in (try? context.fetch(FetchDescriptor<CompletedSessionModel>())) ?? [] {
            for entry in session.entries where !entry.skipped {
                guard let ex = catalog.exercise(id: entry.exerciseID) else { continue }
                let doneSets = entry.sets.filter { !$0.isWarmup }.count
                if doneSets > 0 { effectiveSetItems.append(.init(exercise: ex, sets: doneSets)) }
            }
        }
        let load = MuscleBalanceModel.loadOf(items: effectiveSetItems)
        let (_, missed) = MuscleBalanceModel.rankOf(load: load)

        let slugToMuscle: [String: MuscleGroup] = Dictionary(
            uniqueKeysWithValues: MuscleGroup.allCases.map { (MuscleBalanceModel.canonicalSlug(for: $0), $0) }
        )

        let existingSuggestions = (try? context.fetch(FetchDescriptor<PendingCoachSuggestion>())) ?? []
        let unresolvedExerciseIDs = Set(existingSuggestions.filter { $0.resolvedAt == nil }.map(\.exerciseID))

        for slug in missed {
            guard let muscle = slugToMuscle[slug] else { continue }
            // NOTE (adaptation): CatalogStore has no public `exercises` iteration
            // property — it exposes `all: [Exercise]`, `exercise(id:)` lookup, and
            // `exercises(primaryMuscle:availableEquipment:)` (which requires an
            // equipment filter we don't have here). We iterate `catalog.all`
            // directly instead of adding a new API surface.
            guard let candidate = catalog.all.first(where: { $0.primaryMuscle == muscle }) else { continue }
            guard !unresolvedExerciseIDs.contains(candidate.id) else { continue }

            let suggestion = PendingCoachSuggestion(plannedSessionID: firstSession.id, kind: "addExercise",
                                                    exerciseID: candidate.id,
                                                    rationale: "\(muscle.rawValue.capitalized) hasn't been trained this window.",
                                                    source: "coverageGap")
            suggestion.targetSets = 3
            suggestion.targetRepsMin = 8
            suggestion.targetRepsMax = 12
            context.insert(suggestion)
        }
        try? context.save()
    }
}
