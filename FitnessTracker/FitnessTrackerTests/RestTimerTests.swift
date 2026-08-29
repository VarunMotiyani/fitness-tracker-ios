import Testing
@testable import FitnessTracker

/// Drives `RestTimer` state transitions synchronously via `tick()` — never
/// waits a real second.
@MainActor
@Suite struct RestTimerTests {

    @Test func startSetsRemainingRunningAndTotal() {
        let timer = RestTimer()
        timer.start(seconds: 90)
        #expect(timer.remaining == 90)
        #expect(timer.isRunning == true)
        #expect(timer.total == 90)
    }

    @Test func tickDecrementsOnePerSecond() {
        let timer = RestTimer()
        timer.start(seconds: 90)
        for _ in 0..<5 { timer.tick() }
        #expect(timer.remaining == 85)
        #expect(timer.isRunning == true)
    }

    @Test func addClampsAtZeroAndStops() {
        let timer = RestTimer()
        timer.start(seconds: 90)
        timer.add(-100)
        #expect(timer.remaining == 0)
        #expect(timer.isRunning == false)
    }

    @Test func skipStopsImmediately() {
        let timer = RestTimer()
        timer.start(seconds: 60)
        timer.skip()
        #expect(timer.remaining == 0)
        #expect(timer.isRunning == false)
    }

    @Test func tickPastZeroDoesNotGoNegative() {
        let timer = RestTimer()
        timer.start(seconds: 2)
        timer.tick()
        timer.tick()
        timer.tick()
        timer.tick()
        #expect(timer.remaining == 0)
        #expect(timer.isRunning == false)
    }
}
