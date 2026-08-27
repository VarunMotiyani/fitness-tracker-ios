import Testing
import Foundation
@testable import FitnessDomain

@Test func weeklyPlanEncodesAndDecodesUnchanged() throws {
    let plan = WeeklyPlan(
        weekStartDate: Date(timeIntervalSince1970: 1_700_000_000),
        source: .ruleEngine,
        rationale: "3-day full body",
        sessions: [
            PlannedSession(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                order: 0,
                focusMuscles: [.chest, .back],
                items: [
                    PlannedItem(exerciseID: "Barbell_Bench_Press",
                                targetSets: 3,
                                targetReps: RepRange(min: 5, max: 8),
                                targetLoadKg: nil,
                                restSeconds: 150,
                                coachNote: "Leave 2 reps in the tank.")
                ]
            )
        ],
        weeklyVolumeTargets: [MuscleVolumeTarget(muscle: .chest, targetSets: 12)]
    )

    let data = try JSONEncoder().encode(plan)
    let decoded = try JSONDecoder().decode(WeeklyPlan.self, from: data)
    #expect(decoded == plan)
}

@Test func repRangeIsEquatable() {
    #expect(RepRange(min: 8, max: 12) == RepRange(min: 8, max: 12))
    #expect(RepRange(min: 8, max: 12) != RepRange(min: 8, max: 10))
}
