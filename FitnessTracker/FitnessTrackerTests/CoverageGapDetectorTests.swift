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

    /// Critical #1 regression: `generateAndStore` resolves every pending suggestion
    /// (they necessarily targeted the plan about to be superseded) before inserting
    /// the fresh `StoredPlan` and re-running the coverage-gap detector. Without this,
    /// a `PendingCoachSuggestion` from week N's plan points at a `plannedSessionID`
    /// that no longer exists once week N+1's plan is stored, `SuggestionApplier`
    /// can never resolve it (`sessionNotFound` forever), and it permanently blocks
    /// `CoverageGapDetector` from re-proposing that muscle.
    ///
    /// `generateAndStore` itself needs a live `PlanCoordinator`/provider stack that
    /// isn't practical to stand up in a unit test, so this simulates its exact
    /// resolve-then-insert-then-detect sequence directly against a `ModelContext`.
    @Test func regeneratingAPlanResolvesAnyStillPendingSuggestion() throws {
        let ctx = ModelContext(try container())
        let weekOnePlan = WeeklyPlan(weekStartDate: Date(), source: .ruleEngine, rationale: "week 1",
                              sessions: [PlannedSession(id: UUID(), order: 0, focusMuscles: [.chest], items: [
                                  PlannedItem(exerciseID: "bench", targetSets: 3, targetReps: RepRange(min: 6, max: 8),
                                              targetLoadKg: 60, restSeconds: 90, coachNote: "")
                              ])], weeklyVolumeTargets: [])
        let storedWeekOne = try StoredPlan(plan: weekOnePlan, hadValidationIssues: false)
        ctx.insert(storedWeekOne)
        try ctx.save()

        // A suggestion proposed against week one's plan — e.g. via Ask Coach.
        let stalePending = PendingCoachSuggestion(plannedSessionID: weekOnePlan.sessions[0].id, kind: "exerciseSwap",
                                                  exerciseID: "bench", rationale: "test", source: "askCoach")
        stalePending.replacementExerciseID = "lateral_raise"
        ctx.insert(stalePending)
        try ctx.save()

        // Simulate generateAndStore's resolve-then-insert-then-detect sequence for
        // week two's regeneration.
        let weekTwoPlan = WeeklyPlan(weekStartDate: Date(), source: .ruleEngine, rationale: "week 2",
                              sessions: [PlannedSession(id: UUID(), order: 0, focusMuscles: [.chest], items: [
                                  PlannedItem(exerciseID: "bench", targetSets: 3, targetReps: RepRange(min: 6, max: 8),
                                              targetLoadKg: 60, restSeconds: 90, coachNote: "")
                              ])], weeklyVolumeTargets: [])
        let storedWeekTwo = try StoredPlan(plan: weekTwoPlan, hadValidationIssues: false)
        let allPending = try ctx.fetch(FetchDescriptor<PendingCoachSuggestion>())
        for suggestion in allPending where suggestion.resolvedAt == nil {
            suggestion.resolvedAt = .now
            suggestion.accepted = false
        }
        ctx.insert(storedWeekTwo)
        CoverageGapDetector.detect(context: ctx, catalog: catalog(), storedPlan: storedWeekTwo)
        try ctx.save()

        #expect(stalePending.resolvedAt != nil)
        #expect(stalePending.accepted == false)
    }
}
