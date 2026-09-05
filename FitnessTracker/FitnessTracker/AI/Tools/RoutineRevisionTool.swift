import Foundation
import SwiftData
import CoachMemory
import LLMKit

struct ProposeRoutineRevisionArgs: Decodable {
    let statement: String
    let action: String?
}

/// Writes a durable preference through the same `MemoryConsolidation`
/// pipeline the memory-keeper call uses (design spec §4) — a "permanent"
/// routine change only ever works by feeding the *next* plan generation a
/// preference it reads (Task 1), not by editing a specific week's plan.
@MainActor
struct ProposeRoutineRevisionTool: CoachTool {
    let context: ModelContext

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            name: "propose_routine_revision",
            description: "Record a permanent program preference (not a one-session change) — it will influence future plan generation, not the current week's plan.",
            argsSchemaJSON: "{\"statement\": \"string\", \"action\": \"string|null\"}"
        )
    }

    func run(argsJSON: String) -> String {
        guard let args = decodeArgs(argsJSON, as: ProposeRoutineRevisionArgs.self) else {
            return "{\"error\": \"bad args\"}"
        }
        let existingMemories = ((try? context.fetch(FetchDescriptor<CoachMemoryModel>())) ?? []).map { $0.toDomain() }
        let candidate = MemoryCandidate(kind: .preference, statement: args.statement,
                                        action: args.action, tags: MemoryTags(), relation: .new)
        let result = MemoryConsolidation.reconcile(existing: existingMemories, candidates: [candidate], now: .now)

        for memory in result.writes {
            context.insert(coachMemoryModel(from: memory))
        }
        try? context.save()
        return "{\"status\": \"noted\"}"
    }
}
