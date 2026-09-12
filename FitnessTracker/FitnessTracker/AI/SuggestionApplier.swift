import Foundation
import SwiftData
import FitnessDomain
import CoachMemory
import os

enum SuggestionApplierError: Error {
    case sessionNotFound
    /// The target session exists but doesn't contain `suggestion.exerciseID` —
    /// without this the accept used to mark the suggestion `accepted` and
    /// re-encode the plan *unchanged*, so the card vanished with no effect.
    case itemNotFound
}

/// Applies (or skips) a `PendingCoachSuggestion` against a `StoredPlan`'s
/// encoded `WeeklyPlan`. `apply` decodes the plan, rebuilds the target
/// session's `items` array with the mutation applied, and re-encodes back
/// into `storedPlan.planJSON` — the one deterministic mutation path for
/// accepted suggestions (design spec §3).
@MainActor
enum SuggestionApplier {
    private static let log = Logger(subsystem: "com.varunmotiyani.TrainSage", category: "SuggestionApplier")

    static func apply(_ suggestion: PendingCoachSuggestion, storedPlan: StoredPlan, context: ModelContext) throws {
        let plan = try storedPlan.decodedPlan()
        guard let sessionIndex = plan.sessions.firstIndex(where: { $0.id == suggestion.plannedSessionID }) else {
            log.error("accept \(suggestion.kind, privacy: .public) failed: session \(suggestion.plannedSessionID.uuidString, privacy: .public) not in current plan")
            throw SuggestionApplierError.sessionNotFound
        }
        let session = plan.sessions[sessionIndex]
        var items = session.items

        switch suggestion.kind {
        case "exerciseSwap":
            guard let idx = items.firstIndex(where: { $0.exerciseID == suggestion.exerciseID }),
                  let replacement = suggestion.replacementExerciseID
            else { throw SuggestionApplierError.itemNotFound }
            let old = items[idx]
            items[idx] = PlannedItem(exerciseID: replacement, targetSets: old.targetSets,
                                     targetReps: old.targetReps, targetLoadKg: old.targetLoadKg,
                                     restSeconds: old.restSeconds, coachNote: old.coachNote)
            log.debug("accept swap: \(old.exerciseID, privacy: .public) -> \(replacement, privacy: .public) in session order \(session.order)")
        case "setChange":
            guard let idx = items.firstIndex(where: { $0.exerciseID == suggestion.exerciseID })
            else { throw SuggestionApplierError.itemNotFound }
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
            log.debug("accept setChange \(old.exerciseID, privacy: .public): sets \(old.targetSets)->\(items[idx].targetSets), reps \(old.targetReps.min)-\(old.targetReps.max)->\(items[idx].targetReps.min)-\(items[idx].targetReps.max), load \(old.targetLoadKg ?? -1)->\(items[idx].targetLoadKg ?? -1)")
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

        writeBackOutcome(for: suggestion, accepted: true, context: context)
    }

    static func skip(_ suggestion: PendingCoachSuggestion, context: ModelContext) {
        suggestion.resolvedAt = .now
        suggestion.accepted = false

        writeBackOutcome(for: suggestion, accepted: false, context: context)
    }

    /// Feeds the accept/skip signal back to the source `CoachMemory`'s
    /// `outcomeScore` via `MemoryOutcome.applyResult` (design spec §5.2). Accept
    /// is an `.improved` signal, skip a `.worse` one. If the suggestion has no
    /// source memory, or that row is gone (superseded/evicted), this is a no-op.
    /// The caller is responsible for `context.save()`.
    private static func writeBackOutcome(for suggestion: PendingCoachSuggestion,
                                         accepted: Bool, context: ModelContext) {
        guard let memID = suggestion.sourceMemoryID,
              let model = (try? context.fetch(FetchDescriptor<CoachMemoryModel>()))?
                  .first(where: { $0.id == memID })
        else { return }
        let signal: OutcomeSignal = accepted ? .improved : .worse
        model.outcomeScore = MemoryOutcome.applyResult(to: model.toDomain(), signal: signal).outcomeScore
    }
}
