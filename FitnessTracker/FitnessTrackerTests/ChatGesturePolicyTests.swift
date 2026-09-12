import CoreGraphics
import Testing
@testable import FitnessTracker

@MainActor
struct ChatGesturePolicyTests {
    @Test func verticalScrollWithRightwardDriftDoesNotReply() {
        #expect(!ChatGesturePolicy.shouldReply(width: 72, height: 180, horizontalIntent: false))
    }

    @Test func intentionalHorizontalSwipeRepliesOnlyPastThreshold() {
        #expect(ChatGesturePolicy.shouldReply(width: 72, height: 12, horizontalIntent: true))
        #expect(!ChatGesturePolicy.shouldReply(width: 40, height: 4, horizontalIntent: true))
        #expect(!ChatGesturePolicy.shouldReply(width: -72, height: 4, horizontalIntent: true))
    }
}
