import Testing
import Foundation
import FitnessDomain
@testable import ExerciseCatalog

private let sampleJSON = """
{
  "id": "Alternate_Incline_Dumbbell_Curl",
  "name": "Alternate Incline Dumbbell Curl",
  "force": "pull",
  "level": "beginner",
  "mechanic": "isolation",
  "equipment": "dumbbell",
  "primaryMuscles": ["biceps"],
  "secondaryMuscles": ["forearms"],
  "instructions": ["Sit down on an incline bench."],
  "category": "strength",
  "images": ["Alternate_Incline_Dumbbell_Curl/0.jpg", "Alternate_Incline_Dumbbell_Curl/1.jpg"]
}
""".data(using: .utf8)!

@Test func mapsAKnownRecord() throws {
    let raw = try JSONDecoder().decode(RawFreeExerciseDBExercise.self, from: sampleJSON)
    let ex = try #require(FreeExerciseDBMapper.map(raw))
    #expect(ex.id == "Alternate_Incline_Dumbbell_Curl")
    #expect(ex.primaryMuscle == .biceps)
    #expect(ex.secondaryMuscles == [.forearms])
    #expect(ex.equipment == .dumbbell)
    #expect(ex.mechanic == .isolation)
    #expect(ex.force == .pull)
    #expect(ex.isUnilateral == true)          // "Alternate" in the name
}

@Test func returnsNilWhenPrimaryMuscleUnmappable() throws {
    let json = """
    {"name":"Neck Curl","level":"beginner","primaryMuscles":["shins"],
     "secondaryMuscles":[],"instructions":[],"category":"strength","images":[]}
    """.data(using: .utf8)!
    let raw = try JSONDecoder().decode(RawFreeExerciseDBExercise.self, from: json)
    #expect(FreeExerciseDBMapper.map(raw) == nil)
}

@Test func unknownEquipmentBecomesOther() throws {
    let json = """
    {"name":"Foam Roll IT Band","level":"beginner","equipment":"foam roll",
     "primaryMuscles":["quadriceps"],"secondaryMuscles":[],"instructions":[],
     "category":"stretching","images":[]}
    """.data(using: .utf8)!
    let raw = try JSONDecoder().decode(RawFreeExerciseDBExercise.self, from: json)
    let ex = try #require(FreeExerciseDBMapper.map(raw))
    #expect(ex.equipment == .other)
    #expect(ex.force == nil)
}
