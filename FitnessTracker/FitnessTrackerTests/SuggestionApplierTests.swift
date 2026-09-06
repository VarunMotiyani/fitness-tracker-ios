import Testing
import Foundation
import SwiftData
import FitnessDomain
import CoachMemory
@testable import FitnessTracker

@MainActor
@Suite struct SuggestionApplierTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: StoredPlan.self, PendingCoachSuggestion.self, CoachMemoryModel.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

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

        try SuggestionApplier.apply(suggestion, storedPlan: stored, context: ModelContext(try container()))

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

        try SuggestionApplier.apply(suggestion, storedPlan: stored, context: ModelContext(try container()))

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

        try SuggestionApplier.apply(suggestion, storedPlan: stored, context: ModelContext(try container()))

        let updated = try stored.decodedPlan()
        #expect(updated.sessions[0].items.count == 2)
        #expect(updated.sessions[0].items.last?.exerciseID == "lateral_raise")
    }

    @Test func skipLeavesPlanUntouched() throws {
        let suggestion = PendingCoachSuggestion(plannedSessionID: UUID(), kind: "exerciseSwap",
                                                exerciseID: "bench", rationale: "test", source: "askCoach")
        SuggestionApplier.skip(suggestion, context: ModelContext(try container()))
        #expect(suggestion.resolvedAt != nil)
        #expect(suggestion.accepted == false)
    }

    @Test func applyThrowsForUnknownSession() throws {
        let stored = try StoredPlan(plan: plan(sessionID: UUID()), hadValidationIssues: false)
        let suggestion = PendingCoachSuggestion(plannedSessionID: UUID(), kind: "exerciseSwap",
                                                exerciseID: "bench", rationale: "test", source: "askCoach")
        suggestion.replacementExerciseID = "incline_bench"
        let ctx = ModelContext(try container())
        #expect(throws: (any Error).self) {
            try SuggestionApplier.apply(suggestion, storedPlan: stored, context: ctx)
        }
    }

    // MARK: - MemoryOutcome write-back (spec §5.2)

    private func memoryBackedContext() throws -> (ctx: ModelContext, mem: CoachMemoryModel, stored: StoredPlan, sugg: PendingCoachSuggestion) {
        let ctx = ModelContext(try container())
        let mem = CoachMemoryModel(kindRaw: "preference", statement: "wants more shoulder volume",
                                   confidence: 0.6, sourceKind: "agent",
                                   createdAt: .now, lastConfirmedAt: .now)
        ctx.insert(mem)
        let sessionID = UUID()
        let stored = try StoredPlan(plan: plan(sessionID: sessionID), hadValidationIssues: false)
        ctx.insert(stored)
        let sugg = PendingCoachSuggestion(plannedSessionID: sessionID, kind: "setChange",
                                          exerciseID: "bench", rationale: "you said you want more shoulder volume",
                                          source: "askCoach")
        sugg.sourceMemoryID = mem.id
        sugg.targetSets = 4
        ctx.insert(sugg)
        try ctx.save()
        return (ctx, mem, stored, sugg)
    }

    @Test func acceptingAMemoryBackedSuggestionRaisesOutcomeScore() throws {
        let (ctx, mem, stored, sugg) = try memoryBackedContext()
        #expect(mem.outcomeScore == nil)

        try SuggestionApplier.apply(sugg, storedPlan: stored, context: ctx)
        try ctx.save()

        #expect((mem.outcomeScore ?? 0) > 0)
    }

    @Test func skippingAMemoryBackedSuggestionLowersOutcomeScore() throws {
        let (ctx, mem, _, sugg) = try memoryBackedContext()
        #expect(mem.outcomeScore == nil)

        SuggestionApplier.skip(sugg, context: ctx)
        try ctx.save()

        #expect((mem.outcomeScore ?? 0) < 0)
    }
}
