import Foundation
import LLMKit

/// One capability the coach can invoke mid-reasoning (design spec §4). `run`
/// never throws to its caller — a failure becomes a JSON `{"error": "..."}`
/// string the model can read and react to (e.g. by trying something else or
/// asking a clarifying question), since a thrown Swift error would just
/// crash the tool loop instead of giving the model a chance to recover.
protocol CoachTool: Sendable {
    var descriptor: ToolDescriptor { get }
    func run(argsJSON: String) -> String
}

@MainActor
struct ToolRegistry {
    private let byName: [String: any CoachTool]

    init(tools: [any CoachTool]) {
        var map: [String: any CoachTool] = [:]
        for tool in tools { map[tool.descriptor.name] = tool }
        self.byName = map
    }

    func descriptors() -> [ToolDescriptor] {
        byName.values.map(\.descriptor).sorted { $0.name < $1.name }
    }

    func execute(_ request: ToolCallRequest) -> String {
        guard let tool = byName[request.name] else {
            return "{\"error\": \"unknown tool '\(request.name)'\"}"
        }
        return tool.run(argsJSON: request.argsJSON)
    }
}

/// Decodes a tool's `argsJSON` into a concrete `Decodable` args type,
/// returning `nil` (never throwing) on malformed input from the model.
func decodeArgs<T: Decodable>(_ argsJSON: String, as type: T.Type) -> T? {
    guard let data = argsJSON.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
}

/// Encodes a tool's result value to the JSON string a tool must return.
func encodeResult<T: Encodable>(_ value: T) -> String {
    guard let data = try? JSONEncoder().encode(value),
          let str = String(data: data, encoding: .utf8)
    else { return "{\"error\": \"failed to encode tool result\"}" }
    return str
}

/// Human-readable status text for the chat progress indicator while a tool
/// runs — purely cosmetic, shown live in `ChatView` in place of a static
/// "Coach is thinking…" for however long a multi-step turn takes. Never
/// affects what the tool actually does.
func coachToolStepLabel(for toolName: String) -> String {
    switch toolName {
    case "get_recovery_status": "Checking recovery status…"
    case "get_muscle_balance": "Checking muscle balance…"
    case "query_training_data": "Looking through your training history…"
    case "get_upcoming_sessions": "Checking your schedule…"
    case "propose_exercise_swap", "apply_exercise_swap": "Working out an exercise swap…"
    case "propose_set_change", "apply_set_change": "Adjusting your sets…"
    case "propose_routine_revision": "Noting a routine change…"
    case "start_workout": "Starting your workout…"
    case "regenerate_plan": "Rebuilding your plan…"
    case "set_day_to_rest": "Updating your schedule…"
    case "log_bodyweight": "Logging your weight…"
    case "update_profile": "Updating your profile…"
    case "clear_data": "Clearing your data…"
    default: "Working on it…"
    }
}

/// For tools whose result is a heterogeneous `[String: Any]` (mixing, say, a
/// `Double` and a `[Double]`) rather than a uniform `Encodable` — `JSONSerialization`
/// handles that shape directly where `Encodable` can't.
func encodeJSONObject(_ dict: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: dict),
          let str = String(data: data, encoding: .utf8)
    else { return "{\"error\": \"failed to encode\"}" }
    return str
}
