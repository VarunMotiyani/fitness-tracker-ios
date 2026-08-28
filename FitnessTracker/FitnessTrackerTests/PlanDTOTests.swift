import Testing
import Foundation
import FitnessDomain
import LLMKit
@testable import FitnessTracker

struct PlanDTOTests {
    private let json = """
    {"rationale":"4-day upper/lower",
     "sessions":[{"order":0,"focusMuscles":["chest","back"],
       "items":[{"exerciseID":"Barbell_Bench_Press","sets":3,"repMin":8,"repMax":12,
                 "restSeconds":150,"coachNote":"Leave 2 in the tank."}]}],
     "weeklyVolumeTargets":[{"muscle":"chest","targetSets":16},{"muscle":"nonsense","targetSets":9}]}
    """.data(using: .utf8)!

    @Test func decodesAndMapsToDomain() throws {
        let dto = try JSONDecoder().decode(WeeklyPlanDTO.self, from: json)
        let plan = dto.toDomain(weekStartDate: Date(timeIntervalSince1970: 0), source: .ai)

        #expect(plan.source == .ai)
        #expect(plan.rationale == "4-day upper/lower")
        #expect(plan.sessions.count == 1)
        #expect(plan.sessions[0].focusMuscles == [.chest, .back])
        #expect(plan.sessions[0].items[0].exerciseID == "Barbell_Bench_Press")
        #expect(plan.sessions[0].items[0].targetReps == RepRange(min: 8, max: 12))
        #expect(plan.sessions[0].items[0].targetLoadKg == nil)
        // "nonsense" muscle dropped from volume targets
        #expect(plan.weeklyVolumeTargets.map(\.muscle) == [.chest])
    }

    @Test func schemaIsNonEmptyJSON() {
        #expect(WeeklyPlanDTO.planJSONSchema.json.contains("\"sessions\""))
        #expect(WeeklyPlanDTO.planJSONSchema.json.contains("\"exerciseID\""))
    }
}
