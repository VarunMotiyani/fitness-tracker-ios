import Testing
import Foundation
import FitnessDomain
import CoachMemory
@testable import FitnessTracker

@MainActor
@Suite struct MemoryKeeperDTOTests {
    @Test func decodesFullShapeFromJSON() throws {
        let json = """
        {
          "memoryCandidates": [
            {"kind": "constraint", "statement": "Avoid overhead pressing — shoulder pain reported.",
             "action": "Swap overhead press for chest press", "exerciseID": null, "muscle": "shoulders",
             "equipment": null, "freeTags": [], "relation": "new", "relatedMemoryID": null}
          ],
          "measurementCandidates": [
            {"kind": "bodyFatPercent", "value": 18.2, "unit": "%"}
          ]
        }
        """
        let dto = try JSONDecoder().decode(MemoryKeeperDTO.self, from: Data(json.utf8))
        #expect(dto.memoryCandidates.count == 1)
        #expect(dto.measurementCandidates.count == 1)
        #expect(dto.measurementCandidates[0].value == 18.2)
    }

    @Test func decodesEmptyArrays() throws {
        let json = """
        {"memoryCandidates": [], "measurementCandidates": []}
        """
        let dto = try JSONDecoder().decode(MemoryKeeperDTO.self, from: Data(json.utf8))
        #expect(dto.memoryCandidates.isEmpty)
        #expect(dto.measurementCandidates.isEmpty)
    }

    @Test func toDomainMapsNewRelation() {
        let dto = MemoryCandidateDTO(kind: "preference", statement: "Prefers dumbbells over barbells for pressing.",
                                     action: nil, exerciseID: nil, muscle: nil, equipment: "dumbbell",
                                     freeTags: ["preference"], relation: "new", relatedMemoryID: nil)
        let candidate = dto.toDomain()
        #expect(candidate?.kind == .preference)
        #expect(candidate?.relation == .new)
        #expect(candidate?.tags.equipment == .dumbbell)
    }

    @Test func toDomainMapsReinforcesWithValidUUID() {
        let id = UUID()
        let dto = MemoryCandidateDTO(kind: "observation", statement: "Consistently sore after leg day.",
                                     action: nil, exerciseID: nil, muscle: "quads", equipment: nil,
                                     freeTags: [], relation: "reinforces", relatedMemoryID: id.uuidString)
        let candidate = dto.toDomain()
        #expect(candidate?.relation == .reinforces(id))
    }

    @Test func toDomainFallsBackToNewWhenReinforcesHasNoID() {
        let dto = MemoryCandidateDTO(kind: "observation", statement: "Test.",
                                     action: nil, exerciseID: nil, muscle: nil, equipment: nil,
                                     freeTags: [], relation: "reinforces", relatedMemoryID: nil)
        #expect(dto.toDomain()?.relation == .new)
    }

    @Test func toDomainReturnsNilForUnknownKind() {
        let dto = MemoryCandidateDTO(kind: "bogus", statement: "Test.",
                                     action: nil, exerciseID: nil, muscle: nil, equipment: nil,
                                     freeTags: [], relation: "new", relatedMemoryID: nil)
        #expect(dto.toDomain() == nil)
    }

    @Test func toDomainReturnsNilForUnknownRelation() {
        let dto = MemoryCandidateDTO(kind: "preference", statement: "Test.",
                                     action: nil, exerciseID: nil, muscle: nil, equipment: nil,
                                     freeTags: [], relation: "bogus", relatedMemoryID: nil)
        #expect(dto.toDomain() == nil)
    }
}
