import Testing
import Foundation
import FitnessDomain
import ExerciseCatalog
@testable import RuleEngine

private func testCatalog() -> CatalogStore {
    func ex(_ id: String, _ name: String, _ m: MuscleGroup, _ eq: Equipment, _ mech: Mechanic) -> Exercise {
        Exercise(id: id, name: name, primaryMuscle: m, secondaryMuscles: [], equipment: eq,
                 mechanic: mech, force: nil, difficulty: .beginner, isUnilateral: false,
                 instructions: [], imagePaths: [])
    }
    return CatalogStore(exercises: [
        ex("BB_Bench", "Barbell Bench Press", .chest, .barbell, .compound),
        ex("DB_Press", "Dumbbell Bench Press", .chest, .dumbbell, .compound),
        ex("BB_Row", "Barbell Row", .back, .barbell, .compound),
        ex("BB_Squat", "Barbell Squat", .quads, .barbell, .compound),
        ex("Leg_Curl", "Lying Leg Curl", .hamstrings, .machine, .isolation),
        ex("Hip_Thrust", "Barbell Hip Thrust", .glutes, .barbell, .compound),
        ex("OHP", "Overhead Press", .shoulders, .barbell, .compound),
        ex("Curl", "Barbell Curl", .biceps, .barbell, .isolation),
        ex("Pushdown", "Triceps Pushdown", .triceps, .cable, .isolation),
        ex("Crunch", "Cable Crunch", .abs, .cable, .isolation),
        ex("Calf_Raise", "Standing Calf Raise", .calves, .machine, .isolation),
    ])
}

private func fullEquipmentContext(sessions: Int, goal: Goal = .buildMuscle,
                                  excludedIDs: Set<String> = [],
                                  excludedMuscles: Set<MuscleGroup> = []) -> UserContext {
    UserContext(goal: goal, experience: .intermediate, sessionsPerWeek: sessions,
                sessionLengthMinutes: 60,
                availableEquipment: [.barbell, .dumbbell, .cable, .machine, .bodyweight],
                excludedExerciseIDs: excludedIDs, excludedMuscles: excludedMuscles)
}

@Test func buildsOneSessionPerRequestedDayUpToTemplate() {
    let builder = RulePlanBuilder(catalog: testCatalog())
    let plan = builder.build(context: fullEquipmentContext(sessions: 4), weekStartDate: .init())
    #expect(plan.sessions.count == 4)
    #expect(plan.source == .ruleEngine)
    #expect(plan.sessions.allSatisfy { !$0.items.isEmpty })
}

@Test func neverPrescribesExcludedExerciseOrMuscle() {
    let builder = RulePlanBuilder(catalog: testCatalog())
    let ctx = fullEquipmentContext(sessions: 3, excludedIDs: ["BB_Bench"], excludedMuscles: [.calves])
    let plan = builder.build(context: ctx, weekStartDate: .init())
    let allIDs = plan.sessions.flatMap { $0.items.map(\.exerciseID) }
    #expect(!allIDs.contains("BB_Bench"))
    #expect(!plan.weeklyVolumeTargets.contains { $0.muscle == .calves })
    #expect(!plan.sessions.contains { $0.focusMuscles.contains(.calves) })
}

@Test func weeklyVolumeTargetsUseMAV() {
    let builder = RulePlanBuilder(catalog: testCatalog())
    let plan = builder.build(context: fullEquipmentContext(sessions: 4), weekStartDate: .init())
    let chest = plan.weeklyVolumeTargets.first { $0.muscle == .chest }
    #expect(chest?.targetSets == VolumeLandmarks.band(for: .chest, experience: .intermediate).mav)
}

@Test func repRangeFollowsGoal() {
    let builder = RulePlanBuilder(catalog: testCatalog())
    let plan = builder.build(context: fullEquipmentContext(sessions: 3, goal: .getStronger),
                             weekStartDate: .init())
    let anyItem = plan.sessions.flatMap(\.items).first
    #expect(anyItem?.targetReps == RepRange(min: 4, max: 6))
}

@Test func isDeterministic() {
    let builder = RulePlanBuilder(catalog: testCatalog())
    let ctx = fullEquipmentContext(sessions: 4)
    let a = builder.build(context: ctx, weekStartDate: .init(timeIntervalSince1970: 0))
    let b = builder.build(context: ctx, weekStartDate: .init(timeIntervalSince1970: 0))
    #expect(a.sessions.map { $0.items } == b.sessions.map { $0.items })
    #expect(a.rationale == b.rationale)
}
