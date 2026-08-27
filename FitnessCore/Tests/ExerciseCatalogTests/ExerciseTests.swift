import Testing
import FitnessDomain
@testable import ExerciseCatalog

@Test func exerciseIsIdentifiableByID() {
    let ex = Exercise(id: "Barbell_Bench_Press", name: "Barbell Bench Press",
                      primaryMuscle: .chest, secondaryMuscles: [.triceps, .shoulders],
                      equipment: .barbell, mechanic: .compound, force: .push,
                      difficulty: .beginner, isUnilateral: false,
                      instructions: ["Lie on the bench."], imagePaths: ["Barbell_Bench_Press/0.jpg"])
    #expect(ex.id == "Barbell_Bench_Press")
    #expect(ex.secondaryMuscles.contains(.triceps))
}
