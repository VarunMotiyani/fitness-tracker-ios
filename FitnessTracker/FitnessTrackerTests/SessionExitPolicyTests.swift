import Testing
@testable import FitnessTracker

@Suite struct SessionExitPolicyTests {
    @Test func setupClosesImmediatelyButActiveWorkoutConfirms() {
        #expect(SessionExitPolicy.startScreenRequiresConfirmation == false)
        #expect(SessionExitPolicy.activeWorkoutRequiresConfirmation == true)
    }
}
