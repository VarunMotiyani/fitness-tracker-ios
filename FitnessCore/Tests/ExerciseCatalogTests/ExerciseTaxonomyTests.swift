import Testing
import FitnessDomain
@testable import ExerciseCatalog

private func exercise(_ name: String, primary: MuscleGroup, secondary: [MuscleGroup] = [],
                      force: ForceType? = nil, mechanic: Mechanic = .compound) -> Exercise {
    Exercise(id: name, name: name, primaryMuscle: primary, secondaryMuscles: secondary,
             equipment: .barbell, mechanic: mechanic, force: force, difficulty: .intermediate,
             isUnilateral: false, instructions: [], imagePaths: [])
}

@Test func hingeNameOverridesMisleadingPushForce() {
    let tags = ExerciseTaxonomy.tags(for: exercise("Barbell Deadlift", primary: .glutes, secondary: [.hamstrings, .lowerBack], force: .push))
    #expect(tags.movementPatterns.contains(.hipHinge))
    #expect(!tags.movementPatterns.contains(.horizontalPush))
}

@Test func pushSessionDoesNotReturnBackOnlyExercise() {
    let store = CatalogStore(exercises: [
        exercise("Bench Press", primary: .chest, secondary: [.triceps], force: .push),
        exercise("Barbell Row", primary: .back, secondary: [.biceps], force: .pull)
    ])
    let push = WorkoutFocus.definition(for: .push)
    #expect(store.compatibleExercises(for: push).map(\.name) == ["Bench Press"])
}

@Test func upperSessionReturnsBothPressAndRow() {
    let store = CatalogStore(exercises: [
        exercise("Bench Press", primary: .chest, force: .push),
        exercise("Barbell Row", primary: .back, secondary: [.biceps], force: .pull)
    ])
    let names = Set(store.compatibleExercises(for: WorkoutFocus.definition(for: .upper)).map(\.name))
    #expect(names == ["Bench Press", "Barbell Row"])
}

@Test func explicitMuscleFallbackSupportsCustomFocus() {
    let custom = SessionDefinition(focus: .custom, muscles: [.chest])
    let bench = exercise("Bench", primary: .chest, force: nil)
    #expect(ExerciseTaxonomy.compatibilityScore(bench, session: custom) > 0)
}
