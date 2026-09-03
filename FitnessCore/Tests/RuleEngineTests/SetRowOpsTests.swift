import Testing
import Foundation
import FitnessDomain
import Metrics
@testable import RuleEngine

struct SetRowOpsTests {
    private func baseSet() -> LoggedSetSnapshot {
        let now = Date()
        return LoggedSetSnapshot(
            targetReps: 10,
            targetLoadKg: 100,
            actualReps: 10,
            actualLoadKg: 100,
            startedAt: now,
            completedAt: now,
            restBeforeSec: 90
        )
    }

    @Test func dropSetAddAndRemove() {
        let set = baseSet()
        #expect(set.isDropSet == false)

        let withDrop = SetRowOps.addDrop(to: set, loadKg: 80, reps: 8)
        #expect(withDrop.isDropSet == true)
        #expect(withDrop.drops.count == 1)
        #expect(withDrop.drops.first?.loadKg == 80)
        #expect(withDrop.drops.first?.reps == 8)

        let withoutDrop = SetRowOps.removeDrop(from: withDrop, at: 0)
        #expect(withoutDrop.isDropSet == false)
        #expect(withoutDrop.drops.isEmpty)
    }

    @Test func nextDropLoadAndNextBurstReps() {
        #expect(SetRowOps.nextDropLoad(previousKg: 100, pct: 20) == 80.0)
        #expect(SetRowOps.nextDropLoad(previousKg: 101, pct: 20) == 81.0)
        #expect(SetRowOps.nextBurstReps(previous: 7) == 4)
        #expect(SetRowOps.nextBurstReps(previous: 1) == 1)
    }

    @Test func extraVolumeCountsDropsOnly() {
        var set = baseSet()
        #expect(SetRowOps.extraVolume(set) == 0)

        set = SetRowOps.addDrop(to: set, loadKg: 80, reps: 10)  // 80 * 10 = 800
        set = SetRowOps.addDrop(to: set, loadKg: 60, reps: 10)  // 60 * 10 = 600
        #expect(SetRowOps.extraVolume(set) == 1400.0)
    }

    @Test func splitBurstRepsSumsToTotal() {
        let bursts = SetRowOps.splitBurstReps(total: 12)
        #expect(bursts.reduce(0, +) == 12)
        #expect(bursts == [6, 3, 2, 1])
    }
}
