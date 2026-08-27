import Testing
import Foundation
import FitnessDomain
import ExerciseCatalog
@testable import FitnessTracker

struct PlanServiceTests {

    private func context(sessions: Int = 4,
                         goal: Goal = .buildMuscle,
                         excludedIDs: Set<String> = []) -> UserContext {
        UserContext(goal: goal, experience: .intermediate,
                    sessionsPerWeek: sessions, sessionLengthMinutes: 60,
                    availableEquipment: [.barbell, .dumbbell, .cable, .machine, .bodyweight],
                    excludedExerciseIDs: excludedIDs, excludedMuscles: [])
    }

    @Test func generatesAValidPlanFromTheStubCatalog() throws {
        let service = PlanService(catalog: try BundledCatalog.load())
        let result = service.generate(context: context(), weekStartDate: .init())

        #expect(result.plan.source == .ruleEngine)
        #expect(result.plan.sessions.count == 4)                 // upperLower4 for 4 / intermediate
        #expect(result.plan.sessions.allSatisfy { !$0.items.isEmpty })
        #expect(result.issues.isEmpty, "unexpected issues: \(result.issues)")
    }

    @Test func excludedExerciseNeverAppears() throws {
        let service = PlanService(catalog: try BundledCatalog.load())
        let result = service.generate(context: context(sessions: 3, excludedIDs: ["Barbell_Bench_Press"]),
                                      weekStartDate: .init())
        let ids = result.plan.sessions.flatMap { $0.items.map(\.exerciseID) }
        #expect(!ids.contains("Barbell_Bench_Press"))
    }
}
