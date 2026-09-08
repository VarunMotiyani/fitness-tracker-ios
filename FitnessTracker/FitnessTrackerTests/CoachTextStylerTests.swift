import Testing
@testable import FitnessTracker

@MainActor @Suite struct CoachTextStylerTests {
    @Test func emphasizesTrainingEntitiesAndBoundMetricsOnly() {
        let text = "You logged 20 out of 4 scheduled sessions this week, extending your streak to 13 weeks and hitting seven new personal records, including a 5-rep squat at 140 kg and a 3-rep deadlift at 170 kg. Your upper-body work was solid, but the lower-body and core lagged, especially traps, quads, and hips."

        let segments = CoachTextStyler.emphasizedSegments(in: text)

        #expect(segments.contains("4 scheduled sessions"))
        #expect(segments.contains("13 weeks"))
        #expect(segments.contains("5-rep"))
        #expect(segments.contains("squat"))
        #expect(segments.contains("140 kg"))
        #expect(segments.contains("3-rep"))
        #expect(segments.contains("deadlift"))
        #expect(segments.contains("170 kg"))
        #expect(segments.contains("upper-body"))
        #expect(segments.contains("lower-body"))
        #expect(segments.contains("traps"))
        #expect(segments.contains("quads"))
        #expect(segments.contains("hips"))
    }

    @Test func doesNotEmphasizeGenericCoachingWordsOrUnboundNumbers() {
        let text = "Today, stay focused before the next session. You have two years of experience and should protect your recovery."

        let segments = CoachTextStyler.emphasizedSegments(in: text)

        #expect(segments.isEmpty)
    }

    @Test func preservesCompoundExerciseNamesAsOneSegment() {
        let text = "Add weighted walking lunges and assisted chest dips after your bench press."

        let segments = CoachTextStyler.emphasizedSegments(in: text)

        #expect(segments.contains("weighted walking lunges"))
        #expect(segments.contains("assisted chest dips"))
        #expect(segments.contains("bench press"))
        #expect(!segments.contains("walking"))
        #expect(!segments.contains("dips"))
    }
}
