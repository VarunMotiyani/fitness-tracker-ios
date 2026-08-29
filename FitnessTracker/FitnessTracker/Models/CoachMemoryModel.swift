import Foundation
import SwiftData

/// A persisted coach memory. `MemorySource` is stored as FLAT columns
/// (`sourceKind` = `"agent"` | `"user"`, plus `sourceAgent` when `sourceKind == "agent"`)
/// rather than the synthesised enum-with-payload shape, which is brittle for persistence
/// (Phase 2a follow-up). Every other enum-typed concept is a raw `String` column, and
/// `tagFreeJSON` holds a `[String]` encoded as a JSON array string (default `"[]"`).
@Model
final class CoachMemoryModel {
    var id: UUID
    var kindRaw: String
    var statement: String
    var action: String?
    var confidence: Double
    var sourceKind: String
    var sourceAgent: String?
    var createdAt: Date
    var lastConfirmedAt: Date
    var supersededBy: UUID?
    var retiredByCap: Bool
    var outcomeScore: Double?
    var tagExerciseID: String?
    var tagMuscleRaw: String?
    var tagEquipmentRaw: String?
    var tagFreeJSON: String

    init(id: UUID = UUID(), kindRaw: String, statement: String, confidence: Double,
         sourceKind: String, createdAt: Date, lastConfirmedAt: Date) {
        self.id = id
        self.kindRaw = kindRaw
        self.statement = statement
        self.action = nil
        self.confidence = confidence
        self.sourceKind = sourceKind
        self.sourceAgent = nil
        self.createdAt = createdAt
        self.lastConfirmedAt = lastConfirmedAt
        self.supersededBy = nil
        self.retiredByCap = false
        self.outcomeScore = nil
        self.tagExerciseID = nil
        self.tagMuscleRaw = nil
        self.tagEquipmentRaw = nil
        self.tagFreeJSON = "[]"
    }
}
