import Testing
import Foundation
import FitnessDomain
import Metrics
@testable import FitnessTracker

@MainActor
@Suite struct MemoryKeeperPromptBuilderTests {
    private func session(note: String?) -> CompletedSessionSnapshot {
        CompletedSessionSnapshot(
            id: UUID(), date: Date(), weekday: 2, timeOfDayMinutes: 600,
            plannedDurationMin: 60, actualDurationMin: 55, energy: .normal,
            timeAvailableMin: 60, outcome: .complete, partialReason: nil,
            coachSource: .ai, plannedSessionID: nil, entries: [], overallNote: note
        )
    }

    @Test func systemPromptStatesTheTwoOutputArrays() {
        let prompt = MemoryKeeperPromptBuilder.system()
        #expect(prompt.contains("memoryCandidates"))
        #expect(prompt.contains("measurementCandidates"))
    }

    @Test func userPromptIncludesOverallNote() {
        let prompt = MemoryKeeperPromptBuilder.user(
            session: session(note: "Shoulder felt sore during overhead press."),
            checkin: nil, memoryDigest: ""
        )
        #expect(prompt.contains("Shoulder felt sore during overhead press."))
    }

    @Test func userPromptIncludesCheckinWhenPresent() {
        let checkin = DailyCheckinSnapshot(date: Date(), sleepQuality: 3, soreness: 7, note: "Legs still sore from Monday")
        let prompt = MemoryKeeperPromptBuilder.user(session: session(note: nil), checkin: checkin, memoryDigest: "")
        #expect(prompt.contains("Legs still sore from Monday"))
        #expect(prompt.contains("7"))
    }

    @Test func userPromptOmitsCheckinSectionWhenNil() {
        let prompt = MemoryKeeperPromptBuilder.user(session: session(note: nil), checkin: nil, memoryDigest: "")
        #expect(!prompt.contains("Today's check-in"))
    }

    @Test func userPromptIncludesMemoryDigestWhenNonEmpty() {
        let prompt = MemoryKeeperPromptBuilder.user(session: session(note: nil), checkin: nil,
                                                     memoryDigest: "- Prefers dumbbells over barbells")
        #expect(prompt.contains("Prefers dumbbells over barbells"))
    }

    @Test func userPromptIncludesEntryDetails() {
        let entry = CompletedEntrySnapshot(
            exerciseID: "bench-press", performedOrder: 0, state: .done, skipped: false,
            wasSwappedFrom: nil, feel: .brutal, note: "Left shoulder twinged on the last rep.",
            sets: []
        )
        let sessionWithEntry = CompletedSessionSnapshot(
            id: UUID(), date: Date(), weekday: 2, timeOfDayMinutes: 600,
            plannedDurationMin: 60, actualDurationMin: 55, energy: .normal,
            timeAvailableMin: 60, outcome: .complete, partialReason: nil,
            coachSource: .ai, plannedSessionID: nil, entries: [entry], overallNote: nil
        )
        let prompt = MemoryKeeperPromptBuilder.user(session: sessionWithEntry, checkin: nil, memoryDigest: "")
        #expect(prompt.contains("bench-press"))
        #expect(prompt.contains("Left shoulder twinged on the last rep."))
    }
}
