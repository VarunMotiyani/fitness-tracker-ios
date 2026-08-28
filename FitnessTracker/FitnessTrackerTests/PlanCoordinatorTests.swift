import Testing
import Foundation
import FitnessDomain
import ExerciseCatalog
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
         {"exerciseID":"Barbell_Bench_Press","sets":4,"repMin":8,"repMax":12,"restSeconds":150,"coachNote":"x"},
         {"exerciseID":"Barbell_Row","sets":4,"repMin":8,"repMax":12,"restSeconds":150,"coachNote":"x"},
         {"exerciseID":"Barbell_Back_Squat","sets":4,"repMin":8,"repMax":12,"restSeconds":150,"coachNote":"x"}]},
       {"order":1,"focusMuscles":["chest","back","quads"],"items":[
         {"exerciseID":"Dumbbell_Bench_Press","sets":4,"repMin":8,"repMax":12,"restSeconds":150,"coachNote":"x"},
         {"exerciseID":"Seated_Cable_Row","sets":4,"repMin":8,"repMax":12,"restSeconds":150,"coachNote":"x"},
         {"exerciseID":"Leg_Press","sets":4,"repMin":8,"repMax":12,"restSeconds":150,"coachNote":"x"}]},
       {"order":2,"focusMuscles":["chest","back","quads"],"items":[
         {"exerciseID":"Cable_Crossover","sets":4,"repMin":10,"repMax":15,"restSeconds":90,"coachNote":"x"},
         {"exerciseID":"Lat_Pulldown","sets":4,"repMin":10,"repMax":15,"restSeconds":90,"coachNote":"x"},
         {"exerciseID":"Leg_Extension","sets":4,"repMin":10,"repMax":15,"restSeconds":90,"coachNote":"x"}]}
     ],
     "weeklyVolumeTargets":[{"muscle":"chest","targetSets":12},{"muscle":"back","targetSets":12},{"muscle":"quads","targetSets":12}]}
    """

    @Test func noProviderUsesRuleEngine() async throws {
        let coord = PlanCoordinator(provider: nil, catalog: try catalog())
        let r = await coord.makePlan(context: ctx(), weekStartDate: .init())
        #expect(r.source == .ruleEngine)
        #expect(r.call == nil)
        #expect(r.issues.isEmpty)
    }

    @Test func validAIResponseIsUsed() async throws {
        let stub = StubLLMProvider(responses: [.success(validDTOJSON)])
        let coord = PlanCoordinator(provider: stub, catalog: try catalog())
        let r = await coord.makePlan(context: ctx(), weekStartDate: .init())
        #expect(r.source == .ai)
        #expect(r.issues.isEmpty)
        #expect(r.call?.succeeded == true)
        #expect(stub.callCount == 1)
    }
}
