import Testing
@testable import FitnessTracker

@Suite struct SessionAdvancePolicyTests {
    @Test func completingAnExerciseTargetsTheNextExerciseWithoutOpeningTheList() {
        #expect(SessionAdvancePolicy.nextIndex(currentIndex: 0, entryCount: 3) == 1)
        #expect(SessionAdvancePolicy.nextIndex(currentIndex: 1, entryCount: 3) == 2)
        #expect(SessionAdvancePolicy.nextIndex(currentIndex: 2, entryCount: 3) == nil)
    }
}
