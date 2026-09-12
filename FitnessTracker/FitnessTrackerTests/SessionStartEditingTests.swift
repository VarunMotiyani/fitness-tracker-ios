import Testing
import Foundation
import FitnessDomain
@testable import FitnessTracker

struct SessionStartEditingTests {
    private let first = PlannedItem(
        exerciseID: "push-up", targetSets: 3,
        targetReps: RepRange(min: 8, max: 12), targetLoadKg: nil,
        restSeconds: 90, coachNote: "")
    private let second = PlannedItem(
        exerciseID: "row", targetSets: 4,
        targetReps: RepRange(min: 6, max: 10), targetLoadKg: 40,
        restSeconds: 120, coachNote: "Control the eccentric.")

    @Test func movingAnExerciseUpdatesTheSessionOrder() {
        var draft = SessionStartDraft(items: [first, second])

        draft.moveDown(at: 0)

        #expect(draft.items.map(\.exerciseID) == ["row", "push-up"])
    }

    @Test func movingAtTheBoundaryDoesNothing() {
        var draft = SessionStartDraft(items: [first, second])

        draft.moveUp(at: 0)
        draft.moveDown(at: 1)

        #expect(draft.items.map(\.exerciseID) == ["push-up", "row"])
    }

    @Test func editedItemsArePassedIntoTheStartedSession() {
        let original = PlannedSession(
            id: UUID(), order: 1, focusMuscles: [.chest, .triceps], items: [first, second])
        var draft = SessionStartDraft(items: [first, second])
        draft.moveDown(at: 0)

        let started = draft.plannedSession(basedOn: original)

        #expect(started.id == original.id)
        #expect(started.focusMuscles == original.focusMuscles)
        #expect(started.items.map(\.exerciseID) == ["row", "push-up"])
    }

    @Test func addingAnExerciseAppearsInTheStartedSession() {
        let original = PlannedSession(
            id: UUID(), order: 1, focusMuscles: [.chest, .triceps], items: [first])
        var draft = SessionStartDraft(items: [first])
        draft.append(second)

        let started = draft.plannedSession(basedOn: original)

        #expect(started.items.map(\.exerciseID) == ["push-up", "row"])
    }

    @Test func replacingAnExerciseKeepsItsSessionConfiguration() {
        var draft = SessionStartDraft(items: [first])

        draft.replace(at: 0, with: "incline-press")

        #expect(draft.items[0].exerciseID == "incline-press")
        #expect(draft.items[0].targetSets == first.targetSets)
        #expect(draft.items[0].targetReps == first.targetReps)
        #expect(draft.items[0].restSeconds == first.restSeconds)
    }

    @Test func removingAnExerciseOnlyChangesTheDraft() {
        var draft = SessionStartDraft(items: [first, second])

        let removed = draft.remove(at: 0)

        #expect(removed?.exerciseID == "push-up")
        #expect(draft.items.map(\.exerciseID) == ["row"])
    }

    @Test func shorterTimePreviewDropsTrailingExercises() {
        let preview = SessionStartPlanning.previewItems([first, second], minutes: 10)

        #expect(preview.map(\.exerciseID) == ["push-up"])
    }

    @Test func dragMoveReordersAnExerciseToTheDropTarget() {
        var draft = SessionStartDraft(items: [first, second])

        draft.move(from: 0, to: 1)

        #expect(draft.items.map(\.exerciseID) == ["row", "push-up"])
    }
}
