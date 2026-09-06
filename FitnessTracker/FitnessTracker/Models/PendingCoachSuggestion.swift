import Foundation
import SwiftData

/// A proposed change to one not-yet-started `PlannedSession`, awaiting your
/// Accept/Skip (design spec §3). `kind` is `"exerciseSwap"`, `"setChange"`, or
/// `"addExercise"` (the coverage-gap detector's kind — inserts a new item
/// rather than modifying one). `resolvedAt == nil` means still pending.
@Model
final class PendingCoachSuggestion {
    var id: UUID
    var plannedSessionID: UUID
    var kind: String
    var exerciseID: String
    var replacementExerciseID: String?
    var targetSets: Int?
    var targetRepsMin: Int?
    var targetRepsMax: Int?
    var targetLoadKg: Double?
    var rationale: String
    var source: String
    var createdAt: Date
    var resolvedAt: Date?
    var accepted: Bool?
    /// The `CoachMemory` that drove this proposal, if any — set by the Ask Coach
    /// propose tools from a `[uuid]` line in the memory digest. When set,
    /// `SuggestionApplier` feeds the accept/skip outcome back to that memory's
    /// `outcomeScore` (design spec §5.2).
    var sourceMemoryID: UUID?

    init(plannedSessionID: UUID, kind: String, exerciseID: String, rationale: String, source: String) {
        self.id = UUID()
        self.plannedSessionID = plannedSessionID
        self.kind = kind
        self.exerciseID = exerciseID
        self.replacementExerciseID = nil
        self.targetSets = nil
        self.targetRepsMin = nil
        self.targetRepsMax = nil
        self.targetLoadKg = nil
        self.rationale = rationale
        self.source = source
        self.createdAt = .now
        self.resolvedAt = nil
        self.accepted = nil
        self.sourceMemoryID = nil
    }
}
