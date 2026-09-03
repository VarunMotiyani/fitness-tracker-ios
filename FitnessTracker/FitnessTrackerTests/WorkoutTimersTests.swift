import Testing
@testable import FitnessTracker

@MainActor
@Suite struct WorkoutTimersTests {
    @Test func startRestSetsState() {
        let timers = WorkoutTimers()
        timers.startRest(seconds: 90, forEntryIndex: 2)
        #expect(timers.rest.isRunning == true)
        #expect(timers.rest.totalSeconds == 90)
        #expect(timers.rest.remainingSeconds == 90)
        #expect(timers.rest.entryIndex == 2)
        #expect(timers.work.isRunning == false)
    }

    @Test func startWorkStopsRest() {
        let timers = WorkoutTimers()
        timers.startRest(seconds: 90, forEntryIndex: 1)
        #expect(timers.rest.isRunning == true)

        timers.startWork(seconds: 30, forEntryIndex: 2)
        #expect(timers.rest.isRunning == false)
        #expect(timers.work.isRunning == true)
        #expect(timers.work.totalSeconds == 30)
    }

    @Test func addRestAdjustsRemainingSeconds() {
        let timers = WorkoutTimers()
        timers.startRest(seconds: 60)
        timers.addRest(seconds: 15)
        #expect(timers.rest.remainingSeconds == 75)

        timers.addRest(seconds: -100)
        #expect(timers.rest.isRunning == false)
        #expect(timers.rest.remainingSeconds == 0)
    }

    @Test func shiftOwnerUpdatesEntryIndex() {
        let timers = WorkoutTimers()
        timers.startRest(seconds: 60, forEntryIndex: 3)
        timers.shiftOwner(at: 3, delta: 1)
        #expect(timers.rest.entryIndex == 4)
    }
}
