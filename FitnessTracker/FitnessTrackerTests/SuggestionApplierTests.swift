import Testing
import Foundation
import FitnessDomain
@testable import FitnessTracker

@MainActor
@Suite struct SuggestionApplierTests {
    private func plan(sessionID: UUID) -> WeeklyPlan {
        WeeklyPlan(weekStartDate: Date(), source: .ruleEngine, rationale: "test",
                  sessions: [PlannedSession(id: sessionID, order: 0, focusMuscles: [.chest], items: [
                      PlannedItem(exerciseID: "bench", targetSets: 3, targetReps: RepRange(min: 6, max: 8),
                                  targetLoadKg: 60, restSeconds: 90, coachNote: "")
                  ])],
                  weeklyVolumeTargets: [])
    }

    @Test func applySwapReplacesExerciseID() throws {
        let sessionID = UUID()
        let stored = try StoredPlan(plan: plan(sessionID: sessionID), hadValidationIssues: false)
        let suggestion = PendingCoachSuggestion(plannedSessionID: sessionID, kind: "exerciseSwap",
                                                exerciseID: "bench", rationale: "test", source: "askCoach")
        suggestion.replacementExerciseID = "incline_bench"

        try SuggestionApplier.apply(suggestion, storedPlan: stored)

        let updated = try stored.decodedPlan()
        #expect(updated.sessions[0].items[0].exerciseID == "incline_bench")
        #expect(suggestion.resolvedAt != nil)
        #expect(suggestion.accepted == true)
    }

    @Test func applySetChangeOverridesOnlyGivenFields() throws {
        let sessionID = UUID()
        let stored = try StoredPlan(plan: plan(sessionID: sessionID), hadValidationIssues: false)
        let suggestion = PendingCoachSuggestion(plannedSessionID: sessionID, kind: "setChange",
                                                exerciseID: "bench", rationale: "test", source: "askCoach")
        suggestion.targetSets = 4

        try SuggestionApplier.apply(suggestion, storedPlan: stored)

        let updated = try stored.decodedPlan()
        let item = updated.sessions[0].items[0]
        #expect(item.targetSets == 4)
        #expect(item.targetLoadKg == 60) // unchanged
        #expect(item.targetReps.min == 6) // unchanged
    }

    @Test func applyAddExerciseAppendsNewItem() throws {
        let sessionID = UUID()
        let stored = try StoredPlan(plan: plan(sessionID: sessionID), hadValidationIssues: false)
        let suggestion = PendingCoachSuggestion(plannedSessionID: sessionID, kind: "addExercise",
                                                exerciseID: "lateral_raise", rationale: "test", source: "coverageGap")
        suggestion.targetSets = 3

        try SuggestionApplier.apply(suggestion, storedPlan: stored)

        let updated = try stored.decodedPlan()
        #expect(updated.sessions[0].items.count == 2)
        #expect(updated.sessions[0].items.last?.exerciseID == "lateral_raise")
    }

    @Test func skipLeavesPlanUntouched() {
        let suggestion = PendingCoachSuggestion(plannedSessionID: UUID(), kind: "exerciseSwap",
                                                exerciseID: "bench", rationale: "test", source: "askCoach")
        SuggestionApplier.skip(suggestion)
        #expect(suggestion.resolvedAt != nil)
        #expect(suggestion.accepted == false)
    }

    @Test func applyThrowsForUnknownSession() {
        let stored = try! StoredPlan(plan: plan(sessionID: UUID()), hadValidationIssues: false)
        let suggestion = PendingCoachSuggestion(plannedSessionID: UUID(), kind: "exerciseSwap",
                                                exerciseID: "bench", rationale: "test", source: "askCoach")
        suggestion.replacementExerciseID = "incline_bench"
        #expect(throws: (any Error).self) {
            try SuggestionApplier.apply(suggestion, storedPlan: stored)
        }
    }
}
