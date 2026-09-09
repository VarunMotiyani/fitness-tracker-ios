import Testing
@testable import FitnessTracker

@MainActor @Suite struct WeeklySummaryCopyTests {
    @Test func correctsImpossibleAdherenceWordingInExistingSummary() {
        let body = "You logged 20 out of 4 scheduled sessions this week, extending your streak to 13 weeks."

        let corrected = WeeklySummaryCopy.correctedBody(body, completed: 20, planned: 4)

        #expect(corrected.contains("You completed 20 sessions against a plan of 4 this week"))
        #expect(!corrected.contains("20 out of 4"))
    }

    @Test func leavesValidAdherenceWordingUntouched() {
        let body = "You logged 4 out of 4 scheduled sessions this week."

        #expect(WeeklySummaryCopy.correctedBody(body, completed: 4, planned: 4) == body)
    }
}
