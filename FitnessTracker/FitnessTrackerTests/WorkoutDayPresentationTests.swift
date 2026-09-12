import Foundation
import Testing
import FitnessDomain
@testable import FitnessTracker

@MainActor
struct WorkoutDayPresentationTests {
    @Test func presentsTheScheduledWorkoutAsAPlanNotAReplacementChoice() {
        let session = PlannedSession(
            id: UUID(),
            order: 1,
            focusMuscles: [.back, .biceps],
            items: []
        )

        #expect(WorkoutDayPresentation.title(for: session) == "Pull Day")
        #expect(WorkoutDayPresentation.planLabel(for: session) == "Planned workout")
    }

    @Test func fallsBackToFocusMusclesForCustomSessions() {
        let session = PlannedSession(
            id: UUID(),
            order: 4,
            focusMuscles: [.quads, .hamstrings, .glutes],
            items: []
        )

        #expect(WorkoutDayPresentation.title(for: session) == "Quads, Hamstrings, Glutes")
    }

    @Test func customDayUsesCustomForTodayLabel() {
        #expect(WorkoutDayPresentation.planLabel(isCustomized: true) == "Custom for today")
    }

    @Test func exerciseEditorActionOrderKeepsRestOutOfChangeGroup() {
        #expect(DayEditorActionOrder.visibleActions(showChangeOptions: true) == [
            .plannedWorkout, .changeWorkout, .changeChoices, .resetWorkout, .checkIn, .restToday
        ])
    }
}
