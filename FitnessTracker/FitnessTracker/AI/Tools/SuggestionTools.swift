import Foundation
import SwiftData
import FitnessDomain
import ExerciseCatalog
import LLMKit
import RuleEngine

// Not `private`: `CoachActionTools.swift`'s direct-apply tools need the same
// lookup as the propose-* tools here.
func mostRecentStoredPlan(in context: ModelContext) -> StoredPlan? {
    (try? context.fetch(FetchDescriptor<StoredPlan>(sortBy: [SortDescriptor(\.generatedAt, order: .reverse)])))?.first
}

extension StoredPlan {
    func decodedPlanOrNil() -> WeeklyPlan? { try? decodedPlan() }
}

struct ProposeExerciseSwapArgs: Decodable {
    let plannedSessionID: String
    let exerciseID: String
    let replacementExerciseID: String
    let rationale: String
    let sourceMemoryId: String?
}

/// Writes a `PendingCoachSuggestion`, never mutates the plan directly — only
/// your Accept tap (via `SuggestionApplier`) does that (design spec §4).
@MainActor
struct ProposeExerciseSwapTool: CoachTool {
    let context: ModelContext
    let catalog: CatalogStore
    let sink: CoachActionSink

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            name: "propose_exercise_swap",
            description: "Propose swapping one exercise for another in an upcoming (not yet started) session. Use get_upcoming_sessions first to find the right plannedSessionID.",
            argsSchemaJSON: "{\"plannedSessionID\": \"string\", \"exerciseID\": \"string\", \"replacementExerciseID\": \"string\", \"rationale\": \"string\", \"sourceMemoryId\": \"string? — the [uuid] of the memory that drove this proposal, if any\"}"
        )
    }

    func run(argsJSON: String) -> String {
        guard let args = decodeArgs(argsJSON, as: ProposeExerciseSwapArgs.self),
              let sessionID = UUID(uuidString: args.plannedSessionID)
        else { return "{\"error\": \"bad args\"}" }
        guard catalog.exercise(id: args.replacementExerciseID) != nil else {
            return "{\"error\": \"unknown replacement exercise\"}"
        }
        guard let plan = mostRecentStoredPlan(in: context)?.decodedPlanOrNil(),
              plan.sessions.contains(where: { $0.id == sessionID })
        else { return "{\"error\": \"unknown session\"}" }

        let suggestion = PendingCoachSuggestion(plannedSessionID: sessionID, kind: "exerciseSwap",
                                                exerciseID: args.exerciseID, rationale: args.rationale, source: "askCoach")
        suggestion.replacementExerciseID = args.replacementExerciseID
        suggestion.sourceMemoryID = args.sourceMemoryId.flatMap { UUID(uuidString: $0) }
        context.insert(suggestion)
        _ = PersistenceReporter.attemptSave(context, operation: "persist context")
        // The same `SuggestionCard` Home already shows, now inline in chat too
        // — `SuggestionCardPayload` just carries the id, since ChatView reads
        // the live `PendingCoachSuggestion` for everything else (including
        // whether it's since been resolved from Home).
        sink.addCard(.suggestion, payload: SuggestionCardPayload(suggestionID: suggestion.id))
        return "{\"status\": \"proposed\"}"
    }
}

struct ProposeSetChangeArgs: Decodable {
    let plannedSessionID: String
    let exerciseID: String
    let targetSets: Int?
    let targetRepsMin: Int?
    let targetRepsMax: Int?
    let targetLoadKg: Double?
    let rationale: String
    let sourceMemoryId: String?
}

@MainActor
struct ProposeSetChangeTool: CoachTool {
    let context: ModelContext
    let sink: CoachActionSink

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            name: "propose_set_change",
            description: "Propose changing sets/reps/load for one exercise in an upcoming session. Omit any field you're not changing.",
            argsSchemaJSON: "{\"plannedSessionID\": \"string\", \"exerciseID\": \"string\", \"targetSets\": \"number?\", \"targetRepsMin\": \"number?\", \"targetRepsMax\": \"number?\", \"targetLoadKg\": \"number?\", \"rationale\": \"string\", \"sourceMemoryId\": \"string? — the [uuid] of the memory that drove this proposal, if any\"}"
        )
    }

    func run(argsJSON: String) -> String {
        guard let args = decodeArgs(argsJSON, as: ProposeSetChangeArgs.self),
              let sessionID = UUID(uuidString: args.plannedSessionID)
        else { return "{\"error\": \"bad args\"}" }
        // Match ProposeExerciseSwapTool: a hallucinated session/exercise must
        // fail loudly here, not write a PendingCoachSuggestion that can never
        // resolve (SuggestionApplier would hit sessionNotFound forever).
        guard let plan = mostRecentStoredPlan(in: context)?.decodedPlanOrNil(),
              let session = plan.sessions.first(where: { $0.id == sessionID })
        else { return "{\"error\": \"unknown session — call get_upcoming_sessions first\"}" }
        guard session.items.contains(where: { $0.exerciseID == args.exerciseID }) else {
            return "{\"error\": \"that exercise is not in that session\"}"
        }
        if let sets = args.targetSets, !(1...10).contains(sets) { return "{\"error\": \"implausible sets\"}" }
        if let reps = args.targetRepsMin, !(1...30).contains(reps) { return "{\"error\": \"implausible reps\"}" }
        if let reps = args.targetRepsMax, !(1...30).contains(reps) { return "{\"error\": \"implausible reps\"}" }
        if let load = args.targetLoadKg, !(0...500).contains(load) { return "{\"error\": \"implausible load\"}" }

        let suggestion = PendingCoachSuggestion(plannedSessionID: sessionID, kind: "setChange",
                                                exerciseID: args.exerciseID, rationale: args.rationale, source: "askCoach")
        suggestion.targetSets = args.targetSets
        suggestion.targetRepsMin = args.targetRepsMin
        suggestion.targetRepsMax = args.targetRepsMax
        suggestion.targetLoadKg = args.targetLoadKg
        suggestion.sourceMemoryID = args.sourceMemoryId.flatMap { UUID(uuidString: $0) }
        context.insert(suggestion)
        _ = PersistenceReporter.attemptSave(context, operation: "persist context")
        sink.addCard(.suggestion, payload: SuggestionCardPayload(suggestionID: suggestion.id))
        return "{\"status\": \"proposed\"}"
    }
}

@MainActor
struct GetUpcomingSessionsTool: CoachTool {
    let context: ModelContext
    let catalog: CatalogStore

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            name: "get_upcoming_sessions",
            description: "Lists this week's planned sessions (id, focus muscles, exercises) so you can find the plannedSessionID for a propose_* call.",
            argsSchemaJSON: "{}"
        )
    }

    func run(argsJSON: String) -> String {
        guard let plan = mostRecentStoredPlan(in: context)?.decodedPlanOrNil() else {
            return "{\"error\": \"no plan\"}"
        }
        let cal = WorkoutScheduleStore.calendar
        let weekStart = cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? cal.startOfDay(for: .now)
        // Keep the effective session (one-day exercise edits applied), not just
        // its id — the payload's exercise list must reflect what's actually
        // scheduled for the date, not the recurring routine.
        var scheduledByID: [UUID: (date: String, state: String, session: PlannedSession)] = [:]
        for offset in 0..<7 {
            guard let date = cal.date(byAdding: .day, value: offset, to: weekStart),
                  let session = WorkoutScheduleStore.effectiveSession(for: date, in: plan) else { continue }
            let key = Scheduling.isoDateKey(date, calendar: cal)
            scheduledByID[session.id] = (key, WorkoutScheduleStore.isRescheduled(for: date) ? "rescheduled" : "scheduled", session)
        }
        let payload = plan.sessions.map { planSession -> [String: Any] in
            let scheduled = scheduledByID[planSession.id]
            let session = scheduled?.session ?? planSession
            var item: [String: Any] = [
                "plannedSessionID": session.id.uuidString,
                "order": session.order,
                "focusMuscles": session.focusMuscles.map(\.rawValue),
                "exercises": session.items.map { catalog.exercise(id: $0.exerciseID)?.name ?? $0.exerciseID }
            ]
            if let scheduled {
                item["scheduledDate"] = scheduled.date
                item["scheduleState"] = scheduled.state
            }
            return item
        }
        return encodeJSONObject(["sessions": payload])
    }
}
