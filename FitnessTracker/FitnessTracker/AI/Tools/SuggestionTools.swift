import Foundation
import SwiftData
import FitnessDomain
import ExerciseCatalog
import LLMKit

private func mostRecentStoredPlan(in context: ModelContext) -> StoredPlan? {
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
}

/// Writes a `PendingCoachSuggestion`, never mutates the plan directly — only
/// your Accept tap (via `SuggestionApplier`) does that (design spec §4).
@MainActor
struct ProposeExerciseSwapTool: CoachTool {
    let context: ModelContext
    let catalog: CatalogStore

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            name: "propose_exercise_swap",
            description: "Propose swapping one exercise for another in an upcoming (not yet started) session. Use get_upcoming_sessions first to find the right plannedSessionID.",
            argsSchemaJSON: "{\"plannedSessionID\": \"string\", \"exerciseID\": \"string\", \"replacementExerciseID\": \"string\", \"rationale\": \"string\"}"
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
        context.insert(suggestion)
        try? context.save()
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
}

@MainActor
struct ProposeSetChangeTool: CoachTool {
    let context: ModelContext

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            name: "propose_set_change",
            description: "Propose changing sets/reps/load for one exercise in an upcoming session. Omit any field you're not changing.",
            argsSchemaJSON: "{\"plannedSessionID\": \"string\", \"exerciseID\": \"string\", \"targetSets\": \"number?\", \"targetRepsMin\": \"number?\", \"targetRepsMax\": \"number?\", \"targetLoadKg\": \"number?\", \"rationale\": \"string\"}"
        )
    }

    func run(argsJSON: String) -> String {
        guard let args = decodeArgs(argsJSON, as: ProposeSetChangeArgs.self),
              let sessionID = UUID(uuidString: args.plannedSessionID)
        else { return "{\"error\": \"bad args\"}" }
        if let sets = args.targetSets, !(1...10).contains(sets) { return "{\"error\": \"implausible sets\"}" }
        if let reps = args.targetRepsMax, !(1...30).contains(reps) { return "{\"error\": \"implausible reps\"}" }
        if let load = args.targetLoadKg, !(0...500).contains(load) { return "{\"error\": \"implausible load\"}" }

        let suggestion = PendingCoachSuggestion(plannedSessionID: sessionID, kind: "setChange",
                                                exerciseID: args.exerciseID, rationale: args.rationale, source: "askCoach")
        suggestion.targetSets = args.targetSets
        suggestion.targetRepsMin = args.targetRepsMin
        suggestion.targetRepsMax = args.targetRepsMax
        suggestion.targetLoadKg = args.targetLoadKg
        context.insert(suggestion)
        try? context.save()
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
        let payload = plan.sessions.map { session -> [String: Any] in
            [
                "plannedSessionID": session.id.uuidString,
                "focusMuscles": session.focusMuscles.map(\.rawValue),
                "exercises": session.items.map { catalog.exercise(id: $0.exerciseID)?.name ?? $0.exerciseID }
            ]
        }
        return encodeJSONObject(["sessions": payload])
    }
}
