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
    /// Spec §2/§6: "the least-recently-worked missed muscle... capped" — stop
    /// inserting once this many suggestions have actually landed in one `detect()`
    /// call, so a fresh account's near-empty history doesn't flood Home with one
    /// card per `MuscleGroup`.
    private static let maxSuggestionsPerRun = 3

    static func detect(context: ModelContext, catalog: CatalogStore, storedPlan: StoredPlan) {
        guard let plan = try? storedPlan.decodedPlan(), !plan.sessions.isEmpty else { return }

        // Spec §1/§4: this system only ever touches a session that "hasn't started
        // yet" — exclude any planned session that already has a completed/started
        // `CompletedSessionModel`, rather than blindly targeting `sessions.first`
        // (which is Monday, very likely already done by midweek).
        let startedSessionIDs = Set(((try? context.fetch(FetchDescriptor<CompletedSessionModel>())) ?? [])
            .compactMap(\.plannedSessionID))
        let upcomingSessions = plan.sessions.filter { !startedSessionIDs.contains($0.id) }
        guard !upcomingSessions.isEmpty else { return }

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

        var insertedCount = 0
        for slug in missed {
            guard insertedCount < maxSuggestionsPerRun else { break }
            guard let muscle = slugToMuscle[slug] else { continue }
            // NOTE (adaptation): CatalogStore has no public `exercises` iteration
            // property — it exposes `all: [Exercise]`, `exercise(id:)` lookup, and
            // `exercises(primaryMuscle:availableEquipment:)` (which requires an
            // equipment filter we don't have here). We iterate `catalog.all`
            // directly instead of adding a new API surface.
            guard let candidate = catalog.all.first(where: { $0.primaryMuscle == muscle }) else { continue }
            guard !unresolvedExerciseIDs.contains(candidate.id) else { continue }

            // Prefer an upcoming session that already focuses this exact muscle
            // (spec §6's "already targets a muscle group covering it"), falling
            // back to the first upcoming session otherwise.
            let targetSession = upcomingSessions.first { $0.focusMuscles.contains(muscle) } ?? upcomingSessions.first
            guard let targetSession else { continue }

            let suggestion = PendingCoachSuggestion(plannedSessionID: targetSession.id, kind: "addExercise",
                                                    exerciseID: candidate.id,
                                                    rationale: "\(muscle.rawValue.capitalized) hasn't been trained in your logged history.",
                                                    source: "coverageGap")
            suggestion.targetSets = 3
            suggestion.targetRepsMin = 8
            suggestion.targetRepsMax = 12
            context.insert(suggestion)
            insertedCount += 1
        }
        try? context.save()
    }
}
