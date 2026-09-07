import Testing
import Foundation
@testable import Metrics

@Suite struct NotesTests {
    @Test func standingNoteLooksUpAndTrims() {
        let notes = ["bench": "  Seat notch 3, pin 5  "]
        #expect(Notes.standing(exerciseID: "bench", exNotes: notes) == "Seat notch 3, pin 5")
        #expect(Notes.standing(exerciseID: "squat", exNotes: notes) == nil)
    }

    @Test func pinnedNoteReturnsNewestPinnedEntryNote() {
        let now = Date()
        let s1 = CompletedSessionSnapshot(
            id: UUID(), date: now.addingTimeInterval(-86400 * 5), weekday: 1, timeOfDayMinutes: 600,
            plannedDurationMin: 60, actualDurationMin: 60, energy: .normal, timeAvailableMin: 60,
            outcome: .complete, partialReason: nil, coachSource: .rule, plannedSessionID: nil,
            entries: [
                CompletedEntrySnapshot(
                    exerciseID: "bench", performedOrder: 0, state: .done, skipped: false, wasSwappedFrom: nil,
                    feel: nil, note: "First pin", notePin: true, sets: []
                )
            ], overallNote: nil, excludeFromProgression: false
        )

        let s2 = CompletedSessionSnapshot(
            id: UUID(), date: now.addingTimeInterval(-86400 * 2), weekday: 1, timeOfDayMinutes: 600,
            plannedDurationMin: 60, actualDurationMin: 60, energy: .normal, timeAvailableMin: 60,
            outcome: .complete, partialReason: nil, coachSource: .rule, plannedSessionID: nil,
            entries: [
                CompletedEntrySnapshot(
                    exerciseID: "bench", performedOrder: 0, state: .done, skipped: false, wasSwappedFrom: nil,
                    feel: nil, note: "Newer pin", notePin: true, sets: []
                )
            ], overallNote: nil, excludeFromProgression: false
        )

        let pinned = Notes.pinned(exerciseID: "bench", sessions: [s1, s2])
        #expect(pinned?.note == "Newer pin")
        #expect(pinned?.date == s2.date)
    }

    @Test func clampEnforcesLengthLimit() {
        let short = "Good session"
        #expect(Notes.clamp(short) == "Good session")

        let long = String(repeating: "A", count: 600)
        let clamped = Notes.clamp(long)
        #expect(clamped.count == 500)
    }
}
