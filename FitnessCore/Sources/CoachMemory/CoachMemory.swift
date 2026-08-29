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
    public var retiredByCap: Bool = false

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
        outcomeScore: Double?,
        retiredByCap: Bool = false
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
        self.retiredByCap = retiredByCap
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, statement, action, confidence, source
        case createdAt, lastConfirmedAt, supersededBy, tags, outcomeScore, retiredByCap
    }

    /// Custom decode so persisted `CoachMemory` JSON that predates `retiredByCap`
    /// (Phase 2b data) still decodes, defaulting the missing flag to `false`.
    /// Swift's synthesised `Decodable` ignores stored-property defaults for absent keys.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            kind: try container.decode(MemoryKind.self, forKey: .kind),
            statement: try container.decode(String.self, forKey: .statement),
            action: try container.decodeIfPresent(String.self, forKey: .action),
            confidence: try container.decode(Double.self, forKey: .confidence),
            source: try container.decode(MemorySource.self, forKey: .source),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            lastConfirmedAt: try container.decode(Date.self, forKey: .lastConfirmedAt),
            supersededBy: try container.decodeIfPresent(UUID.self, forKey: .supersededBy),
            tags: try container.decode(MemoryTags.self, forKey: .tags),
            outcomeScore: try container.decodeIfPresent(Double.self, forKey: .outcomeScore),
            retiredByCap: try container.decodeIfPresent(Bool.self, forKey: .retiredByCap) ?? false
        )
    }

    public var isRetired: Bool {
        supersededBy != nil
    }
}
