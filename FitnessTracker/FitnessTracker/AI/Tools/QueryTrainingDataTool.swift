import Foundation
import SwiftData
import ExerciseCatalog
import Metrics
import LLMKit

struct QueryTrainingDataArgs: Decodable { let query: String }

/// Read-only escape hatch into the full training-history export (design spec
/// §4.4) — for an exact historical fact the memory digest doesn't cover.
///
/// The export is **lazy**: `HistoryExportManager.exportFullJSONData` walks every
/// SwiftData table and serialises thousands of objects on the main actor, so it
/// only runs (once, then cached) if the model actually calls this tool during
/// the loop. Most finalize / memory-keeper / Ask-Coach turns never do.
@MainActor
struct QueryTrainingDataTool: CoachTool {
    private let produce: @MainActor () -> Data
    private let memo = Memo()

    @MainActor final class Memo { var json: Data? }

    /// Production: defer the whole-DB serialisation until first use.
    init(context: ModelContext, catalog: CatalogStore) {
        produce = { HistoryExportManager.exportFullJSONData(context: context, catalog: catalog) ?? Data("{}".utf8) }
    }

    /// Pre-built payload — for tests and callers that already hold the JSON.
    init(exportJSON: Data) {
        produce = { exportJSON }
    }

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
        let exportJSON: Data
        if let cached = memo.json {
            exportJSON = cached
        } else {
            exportJSON = produce()
            memo.json = exportJSON
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
