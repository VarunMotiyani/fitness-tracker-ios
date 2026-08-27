import Testing
import Foundation
import FitnessDomain
@testable import ExerciseCatalog

private let twoRecords = """
[
  {"id":"Barbell_Bench_Press","name":"Barbell Bench Press","force":"push","level":"beginner",
   "mechanic":"compound","equipment":"barbell","primaryMuscles":["chest"],
   "secondaryMuscles":["triceps","shoulders"],"instructions":["Lie down."],"category":"strength","images":[]},
  {"id":"Cable_Fly","name":"Cable Fly","force":"push","level":"intermediate",
   "mechanic":"isolation","equipment":"cable","primaryMuscles":["chest"],
   "secondaryMuscles":[],"instructions":["Stand tall."],"category":"strength","images":[]}
]
""".data(using: .utf8)!

@Test func loadsAndIndexesByID() throws {
    let store = try CatalogStore.load(fromJSONData: twoRecords)
    #expect(store.all.count == 2)
    #expect(store.contains(id: "Cable_Fly"))
    #expect(store.exercise(id: "Barbell_Bench_Press")?.primaryMuscle == .chest)
}

@Test func filtersByMuscleAndEquipment() throws {
    let store = try CatalogStore.load(fromJSONData: twoRecords)
    let barbellChest = store.exercises(primaryMuscle: .chest, availableEquipment: [.barbell])
    #expect(barbellChest.map(\.id) == ["Barbell_Bench_Press"])

    let allChest = store.exercises(primaryMuscle: .chest, availableEquipment: [.barbell, .cable])
    #expect(allChest.map(\.id) == ["Barbell_Bench_Press", "Cable_Fly"])   // sorted by name
}

@Test func loadThrowsWhenNothingMaps() {
    let junk = "[]".data(using: .utf8)!
    #expect(throws: CatalogError.empty) {
        _ = try CatalogStore.load(fromJSONData: junk)
    }
}
