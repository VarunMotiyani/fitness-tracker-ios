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

/// For tools whose result is a heterogeneous `[String: Any]` (mixing, say, a
/// `Double` and a `[Double]`) rather than a uniform `Encodable` — `JSONSerialization`
/// handles that shape directly where `Encodable` can't.
func encodeJSONObject(_ dict: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: dict),
          let str = String(data: data, encoding: .utf8)
    else { return "{\"error\": \"failed to encode\"}" }
    return str
}
