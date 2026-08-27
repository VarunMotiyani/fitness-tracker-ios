import Testing
import Foundation
import SwiftData
import FitnessDomain
@testable import FitnessTracker

@MainActor
struct StoredPlanTests {

    private func samplePlan() -> WeeklyPlan {
        WeeklyPlan(
            weekStartDate: Date(timeIntervalSince1970: 1_700_000_000),
            source: .ruleEngine,
            rationale: "3-day full body",
            sessions: [
                PlannedSession(id: UUID(), order: 0, focusMuscles: [.chest],
                    items: [PlannedItem(exerciseID: "Barbell_Bench_Press", targetSets: 3,
                        targetReps: RepRange(min: 8, max: 12), targetLoadKg: nil,
                        restSeconds: 150, coachNote: "Leave 2 in the tank.")])
            ],
            weeklyVolumeTargets: [MuscleVolumeTarget(muscle: .chest, targetSets: 12)]
        )
    }

    @Test func roundTripsPlan() throws {
        let container = try ModelContainer(
            for: StoredPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let original = samplePlan()
        let stored = try StoredPlan(plan: original, hadValidationIssues: false)
        container.mainContext.insert(stored)
        try container.mainContext.save()

        let fetched = try container.mainContext.fetch(FetchDescriptor<StoredPlan>()).first
        #expect(fetched != nil)
        #expect(try fetched?.decodedPlan() == original)
        #expect(fetched?.hadValidationIssues == false)
    }
}
