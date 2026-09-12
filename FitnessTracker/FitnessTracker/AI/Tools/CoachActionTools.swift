import Foundation
import SwiftData
import FitnessDomain
import ExerciseCatalog
import LLMKit
import RuleEngine

/// Direct-action tools: unlike `propose_*` (which write a card the athlete
/// must accept), these mutate state immediately — the whole point of asking
/// for them in chat instead of tapping through the UI. Every successful one
/// also records an `.appliedChange` card via `sink.addCard(...)` so the
/// transcript shows a real confirmation, not just the model's own sentence
/// claiming something happened.

// MARK: - Start a workout

struct StartWorkoutArgs: Decodable {
    let plannedSessionID: String
}

/// Records a `.startWorkout` card — the coordinator can't navigate the UI
/// itself, and doesn't try to: the card carries a "Start Now" button that
/// whichever screen hosts this chat wires to its own `onStartSession`, so the
/// athlete leaves chat only when they actually tap it.
@MainActor
struct StartWorkoutTool: CoachTool {
    let context: ModelContext
    let sink: CoachActionSink

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            name: "start_workout",
            description: "Start a specific planned session right now. Use get_upcoming_sessions first to find the plannedSessionID — never guess one.",
            argsSchemaJSON: "{\"plannedSessionID\": \"string\"}"
        )
    }

    func run(argsJSON: String) -> String {
        guard let args = decodeArgs(argsJSON, as: StartWorkoutArgs.self),
              let sessionID = UUID(uuidString: args.plannedSessionID)
        else { return "{\"error\": \"bad args\"}" }
        guard let plan = mostRecentStoredPlan(in: context)?.decodedPlanOrNil(),
              let session = plan.sessions.first(where: { $0.id == sessionID })
        else { return "{\"error\": \"unknown session — call get_upcoming_sessions first\"}" }
        sink.addCard(.startWorkout, payload: StartWorkoutCardPayload(
            plannedSessionID: sessionID, sessionName: RoutineNaming.dayName(for: session.focusMuscles)))
        return "{\"status\": \"starting\"}"
    }
}

// MARK: - Regenerate the plan

struct RegeneratePlanArgs: Decodable {
    let reason: String?
}

/// Only records the request (`CoachTool.run` is synchronous, and plan
/// generation needs the network) — `AskCoachCoordinator.send()` awaits the
/// actual regeneration itself once the tool loop finishes, reusing the exact
/// `generateAndStore` path Settings and onboarding already use, and inserts/
/// settles the `.planRegeneration` card itself (there's no "applied" fact yet
/// at the point this tool runs, so it has nothing to put on a card).
@MainActor
struct RegeneratePlanTool: CoachTool {
    let sink: CoachActionSink

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            name: "regenerate_plan",
            description: "Rebuild the athlete's whole weekly plan from scratch (e.g. they want to change days-per-week, goal, or overall structure — not a single session edit). Takes a little while; tell them you're on it.",
            argsSchemaJSON: "{\"reason\": \"string? — why, for your own final reply\"}"
        )
    }

    func run(argsJSON: String) -> String {
        sink.requestPlanRegeneration()
        return "{\"status\": \"regenerating\"}"
    }
}

// MARK: - Set a day to rest

struct SetDayToRestArgs: Decodable {
    /// ISO `yyyy-MM-dd`, e.g. from `get_upcoming_sessions`'s `scheduledDate`.
    let date: String
}

@MainActor
struct SetDayToRestTool: CoachTool {
    let sink: CoachActionSink

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            name: "set_day_to_rest",
            description: "Mark one specific calendar date (yyyy-MM-dd) as a rest day, overriding whatever session was scheduled. Only affects that date, not the recurring routine.",
            argsSchemaJSON: "{\"date\": \"string — yyyy-MM-dd\"}"
        )
    }

    func run(argsJSON: String) -> String {
        guard let args = decodeArgs(argsJSON, as: SetDayToRestArgs.self) else {
            return "{\"error\": \"bad args\"}"
        }
        let formatter = DateFormatter()
        formatter.calendar = WorkoutScheduleStore.calendar
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: args.date) else {
            return "{\"error\": \"bad date, expected yyyy-MM-dd\"}"
        }
        let key = Scheduling.isoDateKey(date, calendar: WorkoutScheduleStore.calendar)
        var updated = WorkoutScheduleStore.userDayPlan
        updated[key] = "rest"
        WorkoutScheduleStore.saveDayPlan(updated)
        sink.addCard(.appliedChange, payload: AppliedChangeCardPayload(
            icon: "moon.stars.fill", title: "Day set to rest", detail: args.date))
        return "{\"status\": \"set to rest\"}"
    }
}

// MARK: - Apply an exercise swap / set change immediately

struct ApplyExerciseSwapArgs: Decodable {
    let plannedSessionID: String
    let exerciseID: String
    let replacementExerciseID: String
    let rationale: String
}

/// Same mutation `SuggestionApplier.apply` performs when the athlete taps
/// Accept on a proposal card — this just skips the card. Building a throwaway,
/// never-inserted `PendingCoachSuggestion` and handing it to the same
/// `apply()` reuses its exact tested rebuild logic instead of duplicating it.
@MainActor
struct ApplyExerciseSwapTool: CoachTool {
    let context: ModelContext
    let catalog: CatalogStore
    let sink: CoachActionSink

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            name: "apply_exercise_swap",
            description: "Immediately swap one exercise for another in an upcoming (not yet started) session — no approval card, it's applied right away. Use get_upcoming_sessions first for the plannedSessionID.",
            argsSchemaJSON: "{\"plannedSessionID\": \"string\", \"exerciseID\": \"string\", \"replacementExerciseID\": \"string\", \"rationale\": \"string\"}"
        )
    }

    func run(argsJSON: String) -> String {
        guard let args = decodeArgs(argsJSON, as: ApplyExerciseSwapArgs.self),
              let sessionID = UUID(uuidString: args.plannedSessionID)
        else { return "{\"error\": \"bad args\"}" }
        guard let replacement = catalog.exercise(id: args.replacementExerciseID) else {
            return "{\"error\": \"unknown replacement exercise\"}"
        }
        guard let storedPlan = mostRecentStoredPlan(in: context) else {
            return "{\"error\": \"no plan\"}"
        }
        let suggestion = PendingCoachSuggestion(plannedSessionID: sessionID, kind: "exerciseSwap",
                                                exerciseID: args.exerciseID, rationale: args.rationale, source: "askCoachDirect")
        suggestion.replacementExerciseID = args.replacementExerciseID
        do {
            try SuggestionApplier.apply(suggestion, storedPlan: storedPlan, context: context)
            _ = PersistenceReporter.attemptSave(context, operation: "persist context")
            let originalName = catalog.exercise(id: args.exerciseID)?.name ?? args.exerciseID
            sink.addCard(.appliedChange, payload: AppliedChangeCardPayload(
                icon: "arrow.left.arrow.right", title: "Exercise swapped",
                detail: "\(originalName) → \(replacement.name)"))
            return "{\"status\": \"applied\"}"
        } catch {
            return "{\"error\": \"\(error)\"}"
        }
    }
}

struct ApplySetChangeArgs: Decodable {
    let plannedSessionID: String
    let exerciseID: String
    let targetSets: Int?
    let targetRepsMin: Int?
    let targetRepsMax: Int?
    let targetLoadKg: Double?
    let rationale: String
}

@MainActor
struct ApplySetChangeTool: CoachTool {
    let context: ModelContext
    let catalog: CatalogStore
    let sink: CoachActionSink

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            name: "apply_set_change",
            description: "Immediately change sets/reps/load for one exercise in an upcoming session — no approval card. Omit any field you're not changing.",
            argsSchemaJSON: "{\"plannedSessionID\": \"string\", \"exerciseID\": \"string\", \"targetSets\": \"number?\", \"targetRepsMin\": \"number?\", \"targetRepsMax\": \"number?\", \"targetLoadKg\": \"number?\", \"rationale\": \"string\"}"
        )
    }

    func run(argsJSON: String) -> String {
        guard let args = decodeArgs(argsJSON, as: ApplySetChangeArgs.self),
              let sessionID = UUID(uuidString: args.plannedSessionID)
        else { return "{\"error\": \"bad args\"}" }
        if let sets = args.targetSets, !(1...10).contains(sets) { return "{\"error\": \"implausible sets\"}" }
        if let reps = args.targetRepsMin, !(1...30).contains(reps) { return "{\"error\": \"implausible reps\"}" }
        if let reps = args.targetRepsMax, !(1...30).contains(reps) { return "{\"error\": \"implausible reps\"}" }
        if let load = args.targetLoadKg, !(0...500).contains(load) { return "{\"error\": \"implausible load\"}" }
        guard let storedPlan = mostRecentStoredPlan(in: context) else {
            return "{\"error\": \"no plan\"}"
        }
        let suggestion = PendingCoachSuggestion(plannedSessionID: sessionID, kind: "setChange",
                                                exerciseID: args.exerciseID, rationale: args.rationale, source: "askCoachDirect")
        suggestion.targetSets = args.targetSets
        suggestion.targetRepsMin = args.targetRepsMin
        suggestion.targetRepsMax = args.targetRepsMax
        suggestion.targetLoadKg = args.targetLoadKg
        do {
            try SuggestionApplier.apply(suggestion, storedPlan: storedPlan, context: context)
            _ = PersistenceReporter.attemptSave(context, operation: "persist context")
            var parts: [String] = []
            if let sets = args.targetSets { parts.append("\(sets) sets") }
            if args.targetRepsMin != nil || args.targetRepsMax != nil {
                parts.append("\(args.targetRepsMin ?? 0)-\(args.targetRepsMax ?? 0) reps")
            }
            if let load = args.targetLoadKg { parts.append("\(Int(load))kg") }
            let exerciseName = catalog.exercise(id: args.exerciseID)?.name ?? args.exerciseID
            sink.addCard(.appliedChange, payload: AppliedChangeCardPayload(
                icon: "slider.horizontal.3", title: "\(exerciseName) updated",
                detail: parts.isEmpty ? "Updated" : parts.joined(separator: ", ")))
            return "{\"status\": \"applied\"}"
        } catch {
            return "{\"error\": \"\(error)\"}"
        }
    }
}

// MARK: - Log bodyweight

struct LogBodyweightArgs: Decodable {
    let kg: Double
}

/// Scoped to bodyweight only for now — a completed *set* belongs to a
/// `CompletedSessionModel`/`SessionRunner`'s live in-memory state, and writing
/// one from a background chat tool while a session might be open risks the
/// exact desync class this app's save-coalescer work just fixed. Bodyweight
/// has no such live-session entanglement, so it's safe to write directly.
@MainActor
struct LogBodyweightTool: CoachTool {
    let context: ModelContext
    let sink: CoachActionSink

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            name: "log_bodyweight",
            description: "Log today's bodyweight in kilograms.",
            argsSchemaJSON: "{\"kg\": \"number\"}"
        )
    }

    func run(argsJSON: String) -> String {
        guard let args = decodeArgs(argsJSON, as: LogBodyweightArgs.self),
              args.kg.isFinite, (20...400).contains(args.kg)
        else { return "{\"error\": \"bad or implausible weight\"}" }
        do {
            _ = try BodyweightLogStore.recordSingle(args.kg, in: context)
            sink.addCard(.appliedChange, payload: AppliedChangeCardPayload(
                icon: "scalemass.fill", title: "Bodyweight logged",
                detail: String(format: "%.1f kg", args.kg)))
            return "{\"status\": \"logged\"}"
        } catch {
            return "{\"error\": \"\(error)\"}"
        }
    }
}
