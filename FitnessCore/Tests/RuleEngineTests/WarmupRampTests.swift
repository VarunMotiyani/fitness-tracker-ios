import Testing
import Foundation
import Metrics
@testable import RuleEngine

struct WarmupRampTests {
    private func makeSet(load: Double, isWarmup: Bool, done: Bool = false) -> LoggedSetSnapshot {
        let now = Date()
        return LoggedSetSnapshot(
            targetReps: 10,
            targetLoadKg: load,
            actualReps: done ? 10 : 0,
            actualLoadKg: load,
            startedAt: now,
            completedAt: now,
            restBeforeSec: 90,
            isWarmup: isWarmup
        )
    }

    @Test func rerampProducesAscendingLadder() {
        let rows = [
            makeSet(load: 0, isWarmup: true, done: false),
            makeSet(load: 0, isWarmup: true, done: false),
            makeSet(load: 100, isWarmup: false, done: false),
            makeSet(load: 100, isWarmup: false, done: false)
        ]
        let ramped = WarmupRamp.reramp(rows: rows, step: 2.5)

        // Warmup 0: floor(50 / 2.5) * 2.5 = 50.0
        // Warmup 1: floor((50 + (100-50)/2) / 2.5) * 2.5 = floor(75/2.5)*2.5 = 75.0
        #expect(ramped[0].actualLoadKg == 50.0)
        #expect(ramped[1].actualLoadKg == 75.0)
        #expect(ramped[2].actualLoadKg == 100.0)
        #expect(ramped[3].actualLoadKg == 100.0)
    }

    @Test func rerampPreservesDoneWarmup() {
        let rows = [
            makeSet(load: 40, isWarmup: true, done: true),
            makeSet(load: 0, isWarmup: true, done: false),
            makeSet(load: 100, isWarmup: false, done: false)
        ]
        let ramped = WarmupRamp.reramp(rows: rows, step: 2.5)

        #expect(ramped[0].actualLoadKg == 40.0)
        // Warmup 1 ramps from 40 to 100: floor((40 + 30)/2.5)*2.5 = 70.0
        #expect(ramped[1].actualLoadKg == 70.0)
        #expect(ramped[2].actualLoadKg == 100.0)
    }

    @Test func cascadeWeightPropagatesToUndoneWorkRowsOnly() {
        let rows = [
            makeSet(load: 80, isWarmup: false, done: true),
            makeSet(load: 80, isWarmup: false, done: false),
            makeSet(load: 80, isWarmup: false, done: false)
        ]
        // Change row 1 (the first undone row) to 85
        let cascaded = WarmupRamp.cascadeWeight(rows: rows, from: 1, value: 85)

        #expect(cascaded[0].actualLoadKg == 80) // done row unchanged
        #expect(cascaded[1].actualLoadKg == 80) // source row unchanged by forward cascade
        #expect(cascaded[2].actualLoadKg == 85) // subsequent undone row took 85
    }
}
