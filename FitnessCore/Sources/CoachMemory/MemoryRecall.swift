import Foundation
import FitnessDomain

/// The slice of the current session the coach cares about when recalling memory.
public struct RecallContext: Sendable, Equatable {
    public var exerciseIDs: Set<String>
    public var muscles: Set<MuscleGroup>
    public var equipment: Set<Equipment>

    public init(
        exerciseIDs: Set<String> = [],
        muscles: Set<MuscleGroup> = [],
        equipment: Set<Equipment> = []
    ) {
        self.exerciseIDs = exerciseIDs
        self.muscles = muscles
        self.equipment = equipment
    }
}

/// The result of a recall: the selected memories (post-cap, ranked) plus a
/// human-readable digest of the high-confidence ones.
public struct RecalledMemories: Sendable, Equatable {
    public let selected: [CoachMemory]
    public let digest: String

    public init(selected: [CoachMemory], digest: String) {
        self.selected = selected
        self.digest = digest
    }
}

/// Picks the relevant, highest-value slice of coach memory to feed into an agent call.
public enum MemoryRecall {
    public static func select(
        from memories: [CoachMemory],
        context: RecallContext,
        now: Date,
        maxItems: Int = 8,
        halfLifeDays: Double = 30
    ) -> RecalledMemories {
        let candidates = memories.filter { memory in
            guard !memory.isRetired, !memory.retiredByCap else { return false }
            return isRelevant(memory, context: context)
        }

        let ranked = candidates
            .map { memory in (memory: memory, score: score(memory, now: now, halfLifeDays: halfLifeDays)) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.memory.id.uuidString < rhs.memory.id.uuidString
            }
            .map(\.memory)

        let selected = Array(ranked.prefix(max(0, maxItems)))
        return RecalledMemories(selected: selected, digest: digest(from: selected))
    }

    private static func isRelevant(_ memory: CoachMemory, context: RecallContext) -> Bool {
        switch memory.kind {
        case .preference, .goal, .constraint:
            return true
        case .observation, .responsePattern:
            break
        }

        if let exerciseID = memory.tags.exerciseID, context.exerciseIDs.contains(exerciseID) {
            return true
        }
        if let muscle = memory.tags.muscle, context.muscles.contains(muscle) {
            return true
        }
        if let equipment = memory.tags.equipment, context.equipment.contains(equipment) {
            return true
        }
        return false
    }

    private static func score(_ memory: CoachMemory, now: Date, halfLifeDays: Double) -> Double {
        let recency = recencyWeight(memory.lastConfirmedAt, now: now, halfLifeDays: halfLifeDays)
        let outcomeWeight = 1 + 0.5 * (memory.outcomeScore ?? 0)
        return memory.confidence * recency * outcomeWeight
    }

    private static func digest(from selected: [CoachMemory]) -> String {
        selected
            .filter { $0.confidence >= 0.6 }
            .map { memory in
                var line = "- " + memory.statement
                if let action = memory.action, !action.isEmpty {
                    line += " → " + action
                }
                return line
            }
            .joined(separator: "\n")
    }
}
