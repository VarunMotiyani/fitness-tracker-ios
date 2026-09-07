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
    // "foam roll" is deliberately not used here — it now maps to `.roller`, along with
    // the rest of the Gym Visual / free-exercise-db equipment vocabulary (see
    // `FreeExerciseDBMapper.equipment`). This exercises a string neither dataset uses.
    let json = """
    {"name":"Bungee Resistance Curl","level":"beginner","equipment":"resistance bungee",
     "primaryMuscles":["biceps"],"secondaryMuscles":[],"instructions":[],
     "category":"strength","images":[]}
    """.data(using: .utf8)!
    let raw = try JSONDecoder().decode(RawFreeExerciseDBExercise.self, from: json)
    let ex = try #require(FreeExerciseDBMapper.map(raw))
    #expect(ex.equipment == .other)
    #expect(ex.force == nil)
}

@Test("Expanded equipment vocabulary maps to its own case, not the generic bucket",
      arguments: [
        ("leverage machine", Equipment.leverageMachine),
        ("smith machine", Equipment.smithMachine),
        ("sled machine", Equipment.sled),
        ("stability ball", Equipment.stabilityBall),
        ("exercise ball", Equipment.stabilityBall),
        ("bosu ball", Equipment.stabilityBall),
        ("medicine ball", Equipment.medicineBall),
        ("rope", Equipment.rope),
        ("roller", Equipment.roller),
        ("wheel roller", Equipment.roller),
        ("foam roll", Equipment.roller),
        ("weighted", Equipment.bodyweight),
        ("resistance band", Equipment.bands),
        ("upper body ergometer", Equipment.cardioMachine),
        ("stationary bike", Equipment.cardioMachine),
        ("elliptical machine", Equipment.cardioMachine),
      ])
func expandedEquipmentMapsToItsOwnCase(raw: String, expected: Equipment) {
    #expect(FreeExerciseDBMapper.equipment(raw) == expected)
}
