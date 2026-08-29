import Testing
import Foundation
@testable import Metrics

@Suite struct Estimated1RMTests {
    @Test func epleyKnownValues() {
        #expect(Estimated1RM.epley(loadKg: 100, reps: 1) == 100)          // 1-rep clamps to load
        #expect(abs(Estimated1RM.epley(loadKg: 100, reps: 10) - 133.333) < 0.01)
        #expect(abs(Estimated1RM.epley(loadKg: 60, reps: 5) - 70) < 0.001)
    }
    @Test func epleyNonPositiveRepsIsZero() {
        #expect(Estimated1RM.epley(loadKg: 100, reps: 0) == 0)
        #expect(Estimated1RM.epley(loadKg: 100, reps: -3) == 0)
    }
    @Test func prTypeHasThreeCases() { #expect(PRType.allCases.count == 3) }
}
