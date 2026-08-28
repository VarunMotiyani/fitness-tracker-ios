import Foundation
import FitnessDomain
import LLMKit

nonisolated struct WeeklyPlanDTO: Codable, Sendable, Equatable {
    struct ItemDTO: Codable, Sendable, Equatable {
        var exerciseID: String
        var sets: Int
        var repMin: Int
        var repMax: Int
        var restSeconds: Int
        var coachNote: String
    }
    struct SessionDTO: Codable, Sendable, Equatable {
        var order: Int
        var focusMuscles: [String]
        var items: [ItemDTO]
    }
    struct VolumeDTO: Codable, Sendable, Equatable {
        var muscle: String
        var targetSets: Int
    }

    var rationale: String
    var sessions: [SessionDTO]
    var weeklyVolumeTargets: [VolumeDTO]

    func toDomain(weekStartDate: Date, source: PlanSource) -> WeeklyPlan {
        let mappedSessions = sessions.map { s in
            PlannedSession(
                id: UUID(),
                order: s.order,
                focusMuscles: s.focusMuscles.compactMap { MuscleGroup(rawValue: $0) },
                items: s.items.map { i in
                    PlannedItem(exerciseID: i.exerciseID,
                                targetSets: i.sets,
                                targetReps: RepRange(min: i.repMin, max: i.repMax),
                                targetLoadKg: nil,
                                restSeconds: i.restSeconds,
                                coachNote: i.coachNote)
                }
            )
        }
        let targets = weeklyVolumeTargets.compactMap { v -> MuscleVolumeTarget? in
            guard let m = MuscleGroup(rawValue: v.muscle) else { return nil }
            return MuscleVolumeTarget(muscle: m, targetSets: v.targetSets)
        }
        return WeeklyPlan(weekStartDate: weekStartDate, source: source,
                          rationale: rationale, sessions: mappedSessions,
                          weeklyVolumeTargets: targets)
    }

    static let planJSONSchema = JSONSchema(json: #"""
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["rationale", "sessions", "weeklyVolumeTargets"],
      "properties": {
        "rationale": { "type": "string" },
        "sessions": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["order", "focusMuscles", "items"],
            "properties": {
              "order": { "type": "integer" },
              "focusMuscles": { "type": "array", "items": { "type": "string" } },
              "items": {
                "type": "array",
                "items": {
                  "type": "object",
                  "additionalProperties": false,
                  "required": ["exerciseID", "sets", "repMin", "repMax", "restSeconds", "coachNote"],
                  "properties": {
                    "exerciseID": { "type": "string" },
                    "sets": { "type": "integer" },
                    "repMin": { "type": "integer" },
                    "repMax": { "type": "integer" },
                    "restSeconds": { "type": "integer" },
                    "coachNote": { "type": "string" }
                  }
                }
              }
            }
          }
        },
        "weeklyVolumeTargets": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["muscle", "targetSets"],
            "properties": {
              "muscle": { "type": "string" },
              "targetSets": { "type": "integer" }
            }
          }
        }
      }
    }
    """#)
}
