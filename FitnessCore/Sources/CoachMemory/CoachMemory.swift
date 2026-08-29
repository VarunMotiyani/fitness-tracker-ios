import Foundation
import FitnessDomain

public enum MemoryKind: String, CaseIterable, Sendable, Codable, Equatable {
    case preference
    case constraint
    case observation
    case goal
    case responsePattern
}

public enum MemorySource: Sendable, Codable, Equatable {
    case agent(String)
    case user
}

public struct MemoryTags: Sendable, Codable, Equatable {
    public var exerciseID: String?
    public var muscle: MuscleGroup?
    public var equipment: Equipment?
    public var freeTags: [String]

    public init(exerciseID: String? = nil, muscle: MuscleGroup? = nil, equipment: Equipment? = nil, freeTags: [String] = []) {
        self.exerciseID = exerciseID
        self.muscle = muscle
        self.equipment = equipment
        self.freeTags = freeTags
    }
}

public struct CoachMemory: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public var kind: MemoryKind
    public var statement: String
    public var action: String?
    public var confidence: Double
    public var source: MemorySource
    public var createdAt: Date
    public var lastConfirmedAt: Date
    public var supersededBy: UUID?
    public var tags: MemoryTags
    public var outcomeScore: Double?

    public init(
        id: UUID,
        kind: MemoryKind,
        statement: String,
        action: String?,
        confidence: Double,
        source: MemorySource,
        createdAt: Date,
        lastConfirmedAt: Date,
        supersededBy: UUID?,
        tags: MemoryTags,
        outcomeScore: Double?
    ) {
        self.id = id
        self.kind = kind
        self.statement = statement
        self.action = action
        self.confidence = min(1, max(0, confidence))
        self.source = source
        self.createdAt = createdAt
        self.lastConfirmedAt = lastConfirmedAt
        self.supersededBy = supersededBy
        self.tags = tags
        self.outcomeScore = outcomeScore.map { min(1, max(-1, $0)) }
    }

    public var isRetired: Bool {
        supersededBy != nil
    }
}
