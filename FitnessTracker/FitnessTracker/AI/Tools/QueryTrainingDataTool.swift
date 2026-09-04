import Foundation
import Metrics
import LLMKit

struct QueryTrainingDataArgs: Decodable { let query: String }

/// Read-only escape hatch into the full training-history export (design spec
/// §4.4) — for an exact historical fact the memory digest doesn't cover.
/// `exportJSON` is built once per finalize call from the same payload
/// `HistoryExportManager.exportFullJSONData` already produces for the
/// Settings "Export backup" feature, not a second export path.
@MainActor
struct QueryTrainingDataTool: CoachTool {
    let exportJSON: Data

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            name: "query_training_data",
            description: "Read-only JMESPath-subset query over the full training history export. Use this for an exact historical fact not already in your context — e.g. 'what was my squat max in March'. Cannot modify anything.",
            argsSchemaJSON: "{\"query\": \"string, e.g. workouts[].entries[] | [?exerciseId=='0025']\"}"
        )
    }

    func run(argsJSON: String) -> String {
        guard let args = decodeArgs(argsJSON, as: QueryTrainingDataArgs.self) else {
            return "{\"error\": \"bad args\"}"
        }
        do {
            let result = try PulseQuery.evaluate(args.query, against: exportJSON)
            guard let data = try? JSONSerialization.data(withJSONObject: result.asAny, options: [.fragmentsAllowed]),
                  let str = String(data: data, encoding: .utf8)
            else { return "{\"error\": \"result encode failed\"}" }
            return str
        } catch {
            return "{\"error\": \"\(error)\"}"
        }
    }
}
