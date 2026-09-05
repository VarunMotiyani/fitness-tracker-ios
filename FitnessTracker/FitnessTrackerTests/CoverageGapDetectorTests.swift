import Testing
import SwiftData
import Foundation
import FitnessDomain
import ExerciseCatalog
@testable import FitnessTracker

@MainActor
@Suite struct CoverageGapDetectorTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: StoredPlan.self, PendingCoachSuggestion.self,
                           CompletedSessionModel.self, CompletedEntryModel.self, LoggedSetModel.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func exercise(_ id: String, primary: MuscleGroup) -> Exercise {
        Exercise(id: id, name: id, primaryMuscle: primary, secondaryMuscles: [],
                 equipment: .barbell, mechanic: .compound, force: .push,
                 difficulty: .intermediate, isUnilateral: false, instructions: [], imagePaths: [])
    }

    private func catalog() -> CatalogStore {
        CatalogStore(exercises: [exercise("bench", primary: .chest), exercise("lateral_raise", primary: .shoulders)])
    }

    @Test func proposesAddExerciseForAMissedMuscle() throws {
        let ctx = ModelContext(try container())
        let sessionID = UUID()
        let plan = WeeklyPlan(weekStartDate: Date(), source: .ruleEngine, rationale: "test",
                              sessions: [PlannedSession(id: sessionID, order: 0, focusMuscles: [.chest, .shoulders], items: [
                                  PlannedItem(exerciseID: "bench", targetSets: 3, targetReps: RepRange(min: 6, max: 8),
                                              targetLoadKg: 60, restSeconds: 90, coachNote: "")
                              ])], weeklyVolumeTargets: [])
        let stored = try StoredPlan(plan: plan, hadValidationIssues: false)
        ctx.insert(stored)
        try ctx.save()

        CoverageGapDetector.detect(context: ctx, catalog: catalog(), storedPlan: stored)

        let pending = try ctx.fetch(FetchDescriptor<PendingCoachSuggestion>())
        #expect(pending.contains { $0.kind == "addExercise" })
    }

    @Test func doesNotDuplicateAnUnresolvedSuggestionForTheSameMuscle() throws {
        let ctx = ModelContext(try container())
        let sessionID = UUID()
        let plan = WeeklyPlan(weekStartDate: Date(), source: .ruleEngine, rationale: "test",
                              sessions: [PlannedSession(id: sessionID, order: 0, focusMuscles: [.chest], items: [
                                  PlannedItem(exerciseID: "bench", targetSets: 3, targetReps: RepRange(min: 6, max: 8),
                                              targetLoadKg: 60, restSeconds: 90, coachNote: "")
                              ])], weeklyVolumeTargets: [])
        let stored = try StoredPlan(plan: plan, hadValidationIssues: false)
        ctx.insert(stored)
        try ctx.save()

        CoverageGapDetector.detect(context: ctx, catalog: catalog(), storedPlan: stored)
        let firstCount = try ctx.fetch(FetchDescriptor<PendingCoachSuggestion>()).count
        CoverageGapDetector.detect(context: ctx, catalog: catalog(), storedPlan: stored)
        let secondCount = try ctx.fetch(FetchDescriptor<PendingCoachSuggestion>()).count

        #expect(firstCount == secondCount)
    }
}
