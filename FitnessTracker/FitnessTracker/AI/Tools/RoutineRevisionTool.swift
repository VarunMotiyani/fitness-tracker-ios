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
            argsSchemaJSON: "{\"statement\": \"string — a durable preference in the athlete's own terms, e.g. 'Wants more shoulder volume on push days', not a one-off note about today's session\", \"action\": \"string|null\"}"
        )
    }

    func run(argsJSON: String) -> String {
        guard let args = decodeArgs(argsJSON, as: ProposeRoutineRevisionArgs.self) else {
            return "{\"error\": \"bad args\"}"
        }
        let existingMemories = ((try? context.fetch(FetchDescriptor<CoachMemoryModel>())) ?? []).map { $0.toDomain() }
        let candidate = MemoryCandidate(kind: .preference, statement: args.statement,
                                        action: args.action, tags: MemoryTags(), relation: .new)
        // Athlete-stated preferences start at a higher confidence than the 0.3
        // default (which is calibrated for the memory-keeper LLM's own inferences
        // from a session log) — this is a durable preference the athlete stated
        // directly in chat, and it must clear `MemoryRecall.digest`'s 0.6
        // confidence floor on first write so the very next plan generation reads it.
        let result = MemoryConsolidation.reconcile(existing: existingMemories, candidates: [candidate], now: .now, newConfidence: 0.6)

        for memory in result.writes {
            context.insert(coachMemoryModel(from: memory))
        }
        let existingModels = (try? context.fetch(FetchDescriptor<CoachMemoryModel>())) ?? []
        for memory in result.updated + result.retired {
            guard let model = existingModels.first(where: { $0.id == memory.id }) else { continue }
            model.confidence = memory.confidence
            model.lastConfirmedAt = memory.lastConfirmedAt
            model.action = memory.action
            model.supersededBy = memory.supersededBy
            model.retiredByCap = memory.retiredByCap
        }
        try? context.save()
        return "{\"status\": \"noted\"}"
    }
}
