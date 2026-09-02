import Testing
import Foundation
import FitnessDomain
import ExerciseCatalog
import LLMKit
@testable import FitnessTracker

struct PlanCoordinatorTests {
    private func catalog() throws -> ExerciseCatalog.CatalogStore { try BundledCatalog.load() }
    private func ctx() -> UserContext {
        UserContext(goal: .buildMuscle, experience: .intermediate, sessionsPerWeek: 3,
                    sessionLengthMinutes: 60,
                    availableEquipment: [.barbell, .dumbbell, .cable, .machine],
                    excludedExerciseIDs: [], excludedMuscles: [])
    }
    /// A DTO the stub returns that is valid against the stub catalog + a 3-day full body context.
    private let validDTOJSON = """
    {"rationale":"3-day full body",
     "sessions":[
       {"order":0,"focusMuscles":["chest","back","quads"],"items":[
         {"exerciseID":"0025","sets":4,"repMin":8,"repMax":12,"restSeconds":150,"coachNote":"x"},
         {"exerciseID":"2330","sets":4,"repMin":8,"repMax":12,"restSeconds":150,"coachNote":"x"},
         {"exerciseID":"0043","sets":4,"repMin":8,"repMax":12,"restSeconds":150,"coachNote":"x"}]},
       {"order":1,"focusMuscles":["chest","back","quads"],"items":[
         {"exerciseID":"0047","sets":4,"repMin":8,"repMax":12,"restSeconds":150,"coachNote":"x"},
         {"exerciseID":"0027","sets":4,"repMin":8,"repMax":12,"restSeconds":150,"coachNote":"x"},
         {"exerciseID":"0739","sets":4,"repMin":8,"repMax":12,"restSeconds":150,"coachNote":"x"}]},
       {"order":2,"focusMuscles":["chest","back","quads"],"items":[
         {"exerciseID":"0025","sets":4,"repMin":10,"repMax":15,"restSeconds":90,"coachNote":"x"},
         {"exerciseID":"0027","sets":4,"repMin":10,"repMax":15,"restSeconds":90,"coachNote":"x"},
         {"exerciseID":"0585","sets":4,"repMin":10,"repMax":15,"restSeconds":90,"coachNote":"x"}]}
     ],
     "weeklyVolumeTargets":[{"muscle":"chest","targetSets":12},{"muscle":"back","targetSets":12},{"muscle":"quads","targetSets":12}]}
    """

    /// A structurally-degenerate payload: decodes fine, validates clean against
    /// the frozen `PlanValidator` (which only iterates `sessions`), but has no
    /// sessions at all.
    private let emptySessionsJSON = """
    {"rationale":"placeholder","sessions":[],"weeklyVolumeTargets":[]}
    """

    @Test func noProviderUsesRuleEngine() async throws {
        let coord = PlanCoordinator(provider: nil, catalog: try catalog())
        let r = await coord.makePlan(context: ctx(), weekStartDate: .init())
        #expect(r.source == .ruleEngine)
        #expect(r.calls.isEmpty)
        #expect(r.issues.isEmpty)
    }

    @Test func validAIResponseIsUsed() async throws {
        let stub = StubLLMProvider(responses: [.success(validDTOJSON)])
        let coord = PlanCoordinator(provider: stub, catalog: try catalog())
        let r = await coord.makePlan(context: ctx(), weekStartDate: .init())
        #expect(r.source == .ai)
        #expect(r.issues.isEmpty)
        #expect(r.calls.count == 1)
        #expect(r.calls.first?.succeeded == true)
        #expect(stub.callCount == 1)
    }

    @Test func emptySessionsTwiceFallsBack() async throws {
        let stub = StubLLMProvider(responses: [.success(emptySessionsJSON), .success(emptySessionsJSON)])
        let coord = PlanCoordinator(provider: stub, catalog: try catalog())
        let r = await coord.makePlan(context: ctx(), weekStartDate: .init())
        #expect(stub.callCount == 2)
        #expect(r.source == .fallback)
        #expect(r.calls.count == 2)
        #expect(r.calls.last?.succeeded == false)
    }

    @Test func emptySessionsThenValidUsesAI() async throws {
        let stub = StubLLMProvider(responses: [.success(emptySessionsJSON), .success(validDTOJSON)])
        let coord = PlanCoordinator(provider: stub, catalog: try catalog())
        let r = await coord.makePlan(context: ctx(), weekStartDate: .init())
        #expect(stub.callCount == 2)
        #expect(r.source == .ai)
        #expect(r.calls.count == 2)
        // the retry prompt told the model what was structurally wrong
        #expect(stub.lastUser.localizedCaseInsensitiveContains("no sessions"))
    }

    @Test func retriesOnceThenAcceptsSecond() async throws {
        let badJSON = """
        {"rationale":"bad","sessions":[{"order":0,"focusMuscles":["chest"],"items":[
          {"exerciseID":"Ghost_Lift","sets":3,"repMin":8,"repMax":12,"restSeconds":150,"coachNote":"x"}]}],
         "weeklyVolumeTargets":[]}
        """
        let stub = StubLLMProvider(responses: [.success(badJSON), .success(validDTOJSON)])
        let coord = PlanCoordinator(provider: stub, catalog: try catalog())
        let r = await coord.makePlan(context: ctx(), weekStartDate: .init())
        #expect(stub.callCount == 2)
        #expect(r.source == .ai)
        #expect(r.calls.count == 2)
        #expect(stub.lastUser.localizedCaseInsensitiveContains("previous attempt"))
    }

    @Test func twoBadResponsesFallBackToRuleEngine() async throws {
        let badJSON = """
        {"rationale":"bad","sessions":[{"order":0,"focusMuscles":["chest"],"items":[
          {"exerciseID":"Ghost_Lift","sets":3,"repMin":8,"repMax":12,"restSeconds":150,"coachNote":"x"}]}],
         "weeklyVolumeTargets":[]}
        """
        let stub = StubLLMProvider(responses: [.success(badJSON), .success(badJSON)])
        let coord = PlanCoordinator(provider: stub, catalog: try catalog())
        let r = await coord.makePlan(context: ctx(), weekStartDate: .init())
        #expect(stub.callCount == 2)
        #expect(r.source == .fallback)
        #expect(r.issues.isEmpty)                 // the rule-engine plan itself validates
        #expect(r.calls.count == 2)
        #expect(r.calls.last?.succeeded == false)
    }

    @Test func thrownErrorFallsBack() async throws {
        let stub = StubLLMProvider(responses: [.failure(.rateLimited)])
        let coord = PlanCoordinator(provider: stub, catalog: try catalog())
        let r = await coord.makePlan(context: ctx(), weekStartDate: .init())
        #expect(r.source == .fallback)
        #expect(stub.callCount == 1)
    }
}
