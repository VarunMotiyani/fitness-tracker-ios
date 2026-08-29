import Foundation
import Testing
import CoachMemory
import FitnessDomain

@Suite("CoachMemory")
struct CoachMemoryTests {
    @Test("MemoryKind has exactly 5 cases")
    func memoryKindCases() {
        #expect(MemoryKind.allCases.count == 5)
        let expectedCases: Set<MemoryKind> = [.preference, .constraint, .observation, .goal, .responsePattern]
        #expect(Set(MemoryKind.allCases) == expectedCases)
    }

    @Test("CoachMemory clamps confidence to 0...1")
    func confidenceClamping() {
        let tags = MemoryTags(exerciseID: nil, muscle: nil, equipment: nil, freeTags: [])

        // Test clamping above 1
        let highConfidence = CoachMemory(
            id: UUID(),
            kind: .preference,
            statement: "User prefers dumbbells",
            action: nil,
            confidence: 1.7,
            source: .user,
            createdAt: Date(),
            lastConfirmedAt: Date(),
            supersededBy: nil,
            tags: tags,
            outcomeScore: nil
        )
        #expect(highConfidence.confidence == 1.0)

        // Test clamping below 0
        let lowConfidence = CoachMemory(
            id: UUID(),
            kind: .constraint,
            statement: "User has shoulder issue",
            action: nil,
            confidence: -0.5,
            source: .user,
            createdAt: Date(),
            lastConfirmedAt: Date(),
            supersededBy: nil,
            tags: tags,
            outcomeScore: nil
        )
        #expect(lowConfidence.confidence == 0.0)

        // Test within bounds
        let normalConfidence = CoachMemory(
            id: UUID(),
            kind: .observation,
            statement: "User has good form",
            action: nil,
            confidence: 0.75,
            source: .user,
            createdAt: Date(),
            lastConfirmedAt: Date(),
            supersededBy: nil,
            tags: tags,
            outcomeScore: nil
        )
        #expect(normalConfidence.confidence == 0.75)
    }

    @Test("CoachMemory clamps outcomeScore to -1...1")
    func outcomeScoreClamping() {
        let tags = MemoryTags(exerciseID: nil, muscle: nil, equipment: nil, freeTags: [])

        // Test clamping above 1
        let highScore = CoachMemory(
            id: UUID(),
            kind: .responsePattern,
            statement: "User responded well to high volume",
            action: "Increase volume",
            confidence: 0.8,
            source: .user,
            createdAt: Date(),
            lastConfirmedAt: Date(),
            supersededBy: nil,
            tags: tags,
            outcomeScore: 2.5
        )
        #expect(highScore.outcomeScore == 1.0)

        // Test clamping below -1
        let lowScore = CoachMemory(
            id: UUID(),
            kind: .responsePattern,
            statement: "User responded poorly to low volume",
            action: "Increase volume",
            confidence: 0.8,
            source: .user,
            createdAt: Date(),
            lastConfirmedAt: Date(),
            supersededBy: nil,
            tags: tags,
            outcomeScore: -2.0
        )
        #expect(lowScore.outcomeScore == -1.0)

        // Test within bounds
        let normalScore = CoachMemory(
            id: UUID(),
            kind: .responsePattern,
            statement: "User responded moderately",
            action: "Maintain volume",
            confidence: 0.8,
            source: .user,
            createdAt: Date(),
            lastConfirmedAt: Date(),
            supersededBy: nil,
            tags: tags,
            outcomeScore: 0.5
        )
        #expect(normalScore.outcomeScore == 0.5)
    }

    @Test("CoachMemory computes isRetired from supersededBy")
    func isRetired() {
        let id = UUID()
        let supersedingId = UUID()
        let tags = MemoryTags(exerciseID: nil, muscle: nil, equipment: nil, freeTags: [])

        // Not retired (supersededBy is nil)
        let active = CoachMemory(
            id: id,
            kind: .goal,
            statement: "User goal: gain 10 lbs",
            action: nil,
            confidence: 0.9,
            source: .agent("goalTracker"),
            createdAt: Date(),
            lastConfirmedAt: Date(),
            supersededBy: nil,
            tags: tags,
            outcomeScore: nil
        )
        #expect(active.isRetired == false)

        // Retired (supersededBy is set)
        let retired = CoachMemory(
            id: id,
            kind: .goal,
            statement: "User goal: gain 10 lbs",
            action: nil,
            confidence: 0.9,
            source: .agent("goalTracker"),
            createdAt: Date(),
            lastConfirmedAt: Date(),
            supersededBy: supersedingId,
            tags: tags,
            outcomeScore: nil
        )
        #expect(retired.isRetired == true)
    }

    @Test("MemorySource with agent payload encodes and decodes correctly")
    func memorySourceCodable() throws {
        let source = MemorySource.agent("progressAnalyst")
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let encoded = try encoder.encode(source)
        let decoded = try decoder.decode(MemorySource.self, from: encoded)

        #expect(decoded == source)
    }

    @Test("MemorySource user case encodes and decodes correctly")
    func memorySourceUserCodable() throws {
        let source = MemorySource.user
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let encoded = try encoder.encode(source)
        let decoded = try decoder.decode(MemorySource.self, from: encoded)

        #expect(decoded == source)
    }

    @Test("CoachMemory with agent source and tags round-trips through JSON")
    func coachMemoryRoundTrip() throws {
        let id = UUID()
        let createdDate = Date(timeIntervalSince1970: 1000000)
        let confirmedDate = Date(timeIntervalSince1970: 1000100)

        let tags = MemoryTags(
            exerciseID: "ex123",
            muscle: .chest,
            equipment: .dumbbell,
            freeTags: ["progressive-overload", "form-quality"]
        )

        let original = CoachMemory(
            id: id,
            kind: .observation,
            statement: "User has improved form on bench press",
            action: "Continue with current weight progression",
            confidence: 0.85,
            source: .agent("progressAnalyst"),
            createdAt: createdDate,
            lastConfirmedAt: confirmedDate,
            supersededBy: nil,
            tags: tags,
            outcomeScore: 0.7
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(CoachMemory.self, from: encoded)

        #expect(decoded.id == original.id)
        #expect(decoded.kind == original.kind)
        #expect(decoded.statement == original.statement)
        #expect(decoded.action == original.action)
        #expect(decoded.confidence == original.confidence)
        #expect(decoded.source == original.source)
        #expect(decoded.createdAt == original.createdAt)
        #expect(decoded.lastConfirmedAt == original.lastConfirmedAt)
        #expect(decoded.supersededBy == original.supersededBy)
        #expect(decoded.tags == original.tags)
        #expect(decoded.outcomeScore == original.outcomeScore)
    }

    @Test("MemoryTags has memberwise public init with defaults")
    func memoryTagsInit() {
        // Test default init
        let defaultTags = MemoryTags(exerciseID: nil, muscle: nil, equipment: nil, freeTags: [])
        #expect(defaultTags.exerciseID == nil)
        #expect(defaultTags.muscle == nil)
        #expect(defaultTags.equipment == nil)
        #expect(defaultTags.freeTags == [])

        // Test with values
        let filledTags = MemoryTags(
            exerciseID: "ex456",
            muscle: .biceps,
            equipment: .barbell,
            freeTags: ["strength", "hypertrophy"]
        )
        #expect(filledTags.exerciseID == "ex456")
        #expect(filledTags.muscle == .biceps)
        #expect(filledTags.equipment == .barbell)
        #expect(filledTags.freeTags == ["strength", "hypertrophy"])
    }

    @Test("CoachMemory decodes JSON missing retiredByCap as false (forward-compat)")
    func coachMemoryDecodesWithoutRetiredByCap() throws {
        let id = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "kind": "observation",
            "statement": "legacy row predating retiredByCap",
            "confidence": 0.5,
            "source": { "agent": { "_0": "memoryKeeper" } },
            "createdAt": 1000000,
            "lastConfirmedAt": 1000100,
            "tags": { "freeTags": [] }
        }
        """

        let decoded = try JSONDecoder().decode(CoachMemory.self, from: Data(json.utf8))

        #expect(decoded.id == id)
        #expect(decoded.retiredByCap == false)
        #expect(decoded.isRetired == false)
    }

    @Test("CoachMemory conforms to Identifiable")
    func coachMemoryIdentifiable() {
        let id = UUID()
        let tags = MemoryTags(exerciseID: nil, muscle: nil, equipment: nil, freeTags: [])

        let memory = CoachMemory(
            id: id,
            kind: .preference,
            statement: "Test",
            action: nil,
            confidence: 0.5,
            source: .user,
            createdAt: Date(),
            lastConfirmedAt: Date(),
            supersededBy: nil,
            tags: tags,
            outcomeScore: nil
        )

        #expect(memory.id == id)
    }
}
