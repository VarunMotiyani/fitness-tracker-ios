import Testing
import Foundation
@testable import RuleEngine

struct SupersetFlowTests {
    @Test func unitsGroupsConsecutiveSupersets() {
        let entries = [
            RunnerEntry(id: "1", supersetID: "A"),
            RunnerEntry(id: "2", supersetID: "A"),
            RunnerEntry(id: "3", supersetID: nil),
            RunnerEntry(id: "4", supersetID: "B"),
            RunnerEntry(id: "5", supersetID: "B")
        ]
        let units = SupersetFlow.units(entries)
        #expect(units == [[0, 1], [2], [3, 4]])
    }

    @Test func restAfterSetRules() {
        // Last set of the whole workout -> no rest
        #expect(SupersetFlow.restAfterSet(unitDone: true, lastUnit: true) == false)
        // Set completed in a unit that finishes it, but more exercises remain -> rest
        #expect(SupersetFlow.restAfterSet(unitDone: true, lastUnit: false) == true)
        // Set completed mid-unit -> rest
        #expect(SupersetFlow.restAfterSet(unitDone: false, lastUnit: false) == true)
    }

    @Test func restOnRecheckRespectsRunningTimer() {
        #expect(SupersetFlow.restOnRecheck(timerRunning: true, unitDone: false, lastUnit: false) == false)
        #expect(SupersetFlow.restOnRecheck(timerRunning: false, unitDone: false, lastUnit: false) == true)
    }

    @Test func progressTracksHighWater() {
        var entry = RunnerEntry(id: "1", sets: [
            RunnerSetRow(done: true),
            RunnerSetRow(done: true),
            RunnerSetRow(done: false)
        ])
        let p1 = SupersetFlow.progress(entry: entry, previousHighWater: 0)
        #expect(p1.isNew == true)
        #expect(p1.highWater == 2)

        // Uncheck set 1 (1 done)
        entry.sets[1].done = false
        let p2 = SupersetFlow.progress(entry: entry, previousHighWater: 2)
        #expect(p2.isNew == false)
        #expect(p2.highWater == 2)

        // Re-check set 1 (2 done) -> highWater 2 not exceeded
        entry.sets[1].done = true
        let p3 = SupersetFlow.progress(entry: entry, previousHighWater: 2)
        #expect(p3.isNew == false)
        #expect(p3.highWater == 2)

        // Complete 3rd set (3 done) -> new progress!
        entry.sets[2].done = true
        let p4 = SupersetFlow.progress(entry: entry, previousHighWater: 2)
        #expect(p4.isNew == true)
        #expect(p4.highWater == 3)
    }

    @Test func restSecondsTakesLongestMemberOrFallback() {
        let entries = [
            RunnerEntry(id: "1", restSec: 90),
            RunnerEntry(id: "2", restSec: 180),
            RunnerEntry(id: "3", restSec: nil)
        ]
        #expect(SupersetFlow.restSeconds(entries: entries, unit: [0, 1], defaultRestSec: 60) == 180)
        #expect(SupersetFlow.restSeconds(entries: entries, unit: [2], defaultRestSec: 75) == 75)
    }

    @Test func stepCyclesWithinSupersetUnit() {
        var entries = [
            RunnerEntry(id: "1", sets: [RunnerSetRow(done: true), RunnerSetRow(done: false)]),
            RunnerEntry(id: "2", sets: [RunnerSetRow(done: false), RunnerSetRow(done: false)])
        ]
        let unit = [0, 1]

        // Finished set on 0 -> advances to 1
        let s1 = SupersetFlow.step(entries: entries, unit: unit, from: 0)
        #expect(s1?.nextIdx == 1)
        #expect(s1?.roundDone == false)
        #expect(s1?.unitDone == false)

        // Finished set on 1 (now both have 1 done) -> round done, wraps back to 0
        entries[1].sets[0].done = true
        let s2 = SupersetFlow.step(entries: entries, unit: unit, from: 1)
        #expect(s2?.nextIdx == 0)
        #expect(s2?.roundDone == true)
        #expect(s2?.unitDone == false)

        // Finish all remaining sets
        entries[0].sets[1].done = true
        entries[1].sets[1].done = true
        let s3 = SupersetFlow.step(entries: entries, unit: unit, from: 1)
        #expect(s3?.unitDone == true)
    }
}
