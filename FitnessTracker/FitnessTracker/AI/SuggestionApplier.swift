import Foundation
import FitnessDomain

enum SuggestionApplierError: Error {
    case sessionNotFound
}

/// Applies (or skips) a `PendingCoachSuggestion` against a `StoredPlan`'s
/// encoded `WeeklyPlan`. `apply` decodes the plan, rebuilds the target
/// session's `items` array with the mutation applied, and re-encodes back
/// into `storedPlan.planJSON` — the one deterministic mutation path for
/// accepted suggestions (design spec §3).
@MainActor
enum SuggestionApplier {
    static func apply(_ suggestion: PendingCoachSuggestion, storedPlan: StoredPlan) throws {
        let plan = try storedPlan.decodedPlan()
        guard let sessionIndex = plan.sessions.firstIndex(where: { $0.id == suggestion.plannedSessionID }) else {
            throw SuggestionApplierError.sessionNotFound
        }
        let session = plan.sessions[sessionIndex]
        var items = session.items

        switch suggestion.kind {
        case "exerciseSwap":
            if let idx = items.firstIndex(where: { $0.exerciseID == suggestion.exerciseID }),
               let replacement = suggestion.replacementExerciseID {
                let old = items[idx]
                items[idx] = PlannedItem(exerciseID: replacement, targetSets: old.targetSets,
                                         targetReps: old.targetReps, targetLoadKg: old.targetLoadKg,
                                         restSeconds: old.restSeconds, coachNote: old.coachNote)
            }
        case "setChange":
            if let idx = items.firstIndex(where: { $0.exerciseID == suggestion.exerciseID }) {
                let old = items[idx]
                let repRange = (suggestion.targetRepsMin != nil || suggestion.targetRepsMax != nil)
                    ? RepRange(min: suggestion.targetRepsMin ?? old.targetReps.min,
                              max: suggestion.targetRepsMax ?? old.targetReps.max)
                    : old.targetReps
                items[idx] = PlannedItem(exerciseID: old.exerciseID,
                                         targetSets: suggestion.targetSets ?? old.targetSets,
                                         targetReps: repRange,
                                         targetLoadKg: suggestion.targetLoadKg ?? old.targetLoadKg,
                                         restSeconds: old.restSeconds, coachNote: old.coachNote)
            }
        case "addExercise":
            items.append(PlannedItem(exerciseID: suggestion.exerciseID,
                                     targetSets: suggestion.targetSets ?? 3,
                                     targetReps: RepRange(min: suggestion.targetRepsMin ?? 8, max: suggestion.targetRepsMax ?? 12),
                                     targetLoadKg: suggestion.targetLoadKg, restSeconds: 90, coachNote: ""))
        default:
            break
        }

        let updatedSession = PlannedSession(id: session.id, order: session.order,
                                            focusMuscles: session.focusMuscles, items: items)
        var sessions = plan.sessions
        sessions[sessionIndex] = updatedSession
        let updatedPlan = WeeklyPlan(weekStartDate: plan.weekStartDate, source: plan.source,
                                     rationale: plan.rationale, sessions: sessions,
                                     weeklyVolumeTargets: plan.weeklyVolumeTargets)
        storedPlan.planJSON = try JSONEncoder().encode(updatedPlan)

        suggestion.resolvedAt = .now
        suggestion.accepted = true
    }

    static func skip(_ suggestion: PendingCoachSuggestion) {
        suggestion.resolvedAt = .now
        suggestion.accepted = false
    }
}
