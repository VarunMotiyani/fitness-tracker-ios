import Testing
@testable import FitnessTracker

@Suite struct SessionFinalizeTimeoutTests {
    @Test func slowFinalizationFailsFast() async {
        await #expect(throws: SessionFinalizationTimeoutError.self) {
            try await SessionFinalizationTimeout.run(.milliseconds(1)) {
                try await Task.sleep(for: .seconds(30))
                return 42
            }
        }
    }
}
