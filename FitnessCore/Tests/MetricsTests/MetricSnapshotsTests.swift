import Testing
import Foundation
@testable import Metrics

@Suite struct MetricSnapshotsTests {
    @Test func sessionSnapshotRoundTripsThroughCodable() throws {
        let set = LoggedSetSnapshot(targetReps: 8, targetLoadKg: 60, actualReps: 8,
            actualLoadKg: 60, startedAt: Date(timeIntervalSince1970: 0),
            completedAt: Date(timeIntervalSince1970: 40), restBeforeSec: 120,
            rpe: 8, isWarmup: false, isDropSet: false, toFailure: false, assisted: false)
        let entry = CompletedEntrySnapshot(exerciseID: "bench", performedOrder: 0,
            state: .done, skipped: false, wasSwappedFrom: nil, feel: .right,
            note: nil, sets: [set])
        let session = CompletedSessionSnapshot(id: UUID(), date: Date(timeIntervalSince1970: 100),
            weekday: 2, timeOfDayMinutes: 1080, plannedDurationMin: 60, actualDurationMin: 58,
            energy: .normal, timeAvailableMin: 60, outcome: .complete, partialReason: nil,
            coachSource: .rule, plannedSessionID: nil, entries: [entry], overallNote: "solid")

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(CompletedSessionSnapshot.self, from: data)
        #expect(decoded == session)
    }

    @Test func partialReasonHasAllSixCases() {
        #expect(PartialReason.allCases.count == 6)
    }
}
