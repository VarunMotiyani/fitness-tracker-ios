import Testing
import Foundation
import FitnessDomain
import ExerciseCatalog
import RuleEngine
@testable import PlanValidation

private func catalog() -> CatalogStore {
    CatalogStore(exercises: [
        Exercise(id: "BB_Bench", name: "Barbell Bench Press", primaryMuscle: .chest,
                 secondaryMuscles: [], equipment: .barbell, mechanic: .compound, force: .push,
                 difficulty: .beginner, isUnilateral: false, instructions: [], imagePaths: [])
    ])
}

private func item(_ id: String, sets: Int) -> PlannedItem {
    PlannedItem(exerciseID: id, targetSets: sets, targetReps: RepRange(min: 8, max: 12),
                targetLoadKg: nil, restSeconds: 150, coachNote: "")
}

private func plan(_ items: [PlannedItem], targets: [MuscleVolumeTarget] = []) -> WeeklyPlan {
    WeeklyPlan(weekStartDate: .init(), source: .ai, rationale: "",
               sessions: [PlannedSession(id: UUID(), order: 0, focusMuscles: [.chest], items: items)],
               weeklyVolumeTargets: targets)
}

private func ctx(excludedIDs: Set<String> = [], excludedMuscles: Set<MuscleGroup> = []) -> UserContext {
    UserContext(goal: .buildMuscle, experience: .intermediate, sessionsPerWeek: 3,
                sessionLengthMinutes: 60, availableEquipment: [.barbell],
                excludedExerciseIDs: excludedIDs, excludedMuscles: excludedMuscles)
}

@Test func validPlanReturnsNoIssues() {
    // chest intermediate band is 8...22; 12 sets is inside.
    let v = PlanValidator(catalog: catalog())
    let issues = v.validate(plan([item("BB_Bench", sets: 12)]), context: ctx())
    #expect(issues.isEmpty)
}

@Test func flagsUnknownExerciseID() {
    let v = PlanValidator(catalog: catalog())
    let issues = v.validate(plan([item("Ghost_Lift", sets: 12)]), context: ctx())
    #expect(issues.contains(.unknownExerciseID("Ghost_Lift")))
}

@Test func flagsExcludedExercise() {
    let v = PlanValidator(catalog: catalog())
    let issues = v.validate(plan([item("BB_Bench", sets: 12)]),
                            context: ctx(excludedIDs: ["BB_Bench"]))
    #expect(issues.contains(.excludedExercisePresent("BB_Bench")))
}

@Test func flagsExcludedMuscle() {
    let v = PlanValidator(catalog: catalog())
    let issues = v.validate(plan([item("BB_Bench", sets: 12)]),
                            context: ctx(excludedMuscles: [.chest]))
    #expect(issues.contains(.excludedMusclePresent(.chest)))
}

@Test func flagsVolumeAboveMRV() {
    let v = PlanValidator(catalog: catalog())
    let issues = v.validate(plan([item("BB_Bench", sets: 40)]), context: ctx())
    let band = VolumeLandmarks.band(for: .chest, experience: .intermediate)
    #expect(issues.contains(.weeklyVolumeOutOfBand(muscle: .chest, actualSets: 40, band: band)))
}

@Test func flagsEmptySession() {
    let v = PlanValidator(catalog: catalog())
    let issues = v.validate(plan([]), context: ctx())
    #expect(issues.contains(.emptySession(order: 0)))
}
