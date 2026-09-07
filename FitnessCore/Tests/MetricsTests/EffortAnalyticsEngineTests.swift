import Testing
import Foundation
import FitnessDomain
@testable import Metrics

@Suite struct EffortAnalyticsEngineTests {
    private func makeSet(reps: Int = 10, loadKg: Double = 80, rir: Double? = nil, rpe: Double? = nil, isWarmup: Bool = false) -> LoggedSetSnapshot {
        let now = Date()
        return LoggedSetSnapshot(
            targetReps: reps, targetLoadKg: loadKg, actualReps: reps, actualLoadKg: loadKg,
            startedAt: now, completedAt: now.addingTimeInterval(30), restBeforeSec: 60,
            rpe: rpe, isWarmup: isWarmup, rir: rir
        )
    }

    private func makeSession(date: Date, sets: [LoggedSetSnapshot]) -> CompletedSessionSnapshot {
        let entry = CompletedEntrySnapshot(exerciseID: "bench", performedOrder: 0, state: .done, skipped: false, wasSwappedFrom: nil, feel: nil, note: nil, sets: sets)
        return CompletedSessionSnapshot(
            id: UUID(), date: date, weekday: 1, timeOfDayMinutes: 600, plannedDurationMin: 60, actualDurationMin: 60,
            energy: .normal, timeAvailableMin: 60, outcome: .complete, partialReason: nil, coachSource: .rule,
            plannedSessionID: nil, entries: [entry], overallNote: nil, excludeFromProgression: false
        )
    }

    @Test func fourRatedSetsYieldsNilSummaryAverages() {
        let now = Date()
        let sets = [
            makeSet(rir: 2),
            makeSet(rir: 2),
            makeSet(rir: 2),
            makeSet(rir: 2) // 4 rated sets (< 5 threshold)
        ]
        let session = makeSession(date: now, sets: sets)
        let summary = EffortAnalyticsEngine.computeSummary(from: [session], now: now)

        #expect(summary.ratedSets == 4)
        #expect(summary.totalSets == 4)
        #expect(summary.averageRIR == nil)
        #expect(summary.hardSetsPercentage == nil)
    }

    @Test func sixRatedSetsYieldsSummaryAverages() {
        let now = Date()
        let sets = [
            makeSet(rir: 1),
            makeSet(rir: 2),
            makeSet(rir: 3),
            makeSet(rpe: 8), // rpe 8 -> rir 2
            makeSet(rpe: 9), // rpe 9 -> rir 1
            makeSet(rir: 4)  // not hard
        ] // total rated = 6, rirs: [1, 2, 3, 2, 1, 4] -> sum = 13 -> avg = 2.2, hard: 5 / 6 = 0.833...
        let session = makeSession(date: now, sets: sets)
        let summary = EffortAnalyticsEngine.computeSummary(from: [session], now: now)

        #expect(summary.ratedSets == 6)
        #expect(summary.totalSets == 6)
        #expect(summary.averageRIR == 2.2)
        #expect(abs((summary.hardSetsPercentage ?? 0) - (5.0 / 6.0)) < 0.01)
    }

    @Test func weeklyTrendsDropsWeeksWithFewerThanTwoRatedSets() {
        let now = Date()
        let s1 = makeSession(date: now.addingTimeInterval(-86400 * 14), sets: [makeSet(rir: 2)]) // only 1 rated set in this week -> dropped
        let s2 = makeSession(date: now, sets: [makeSet(rir: 1), makeSet(rir: 3)]) // 2 rated sets -> included

        let trends = EffortAnalyticsEngine.computeWeeklyTrends(from: [s1, s2], now: now)
        #expect(trends.count == 1)
        #expect(trends.first?.averageRIR == 2.0)
    }

    @Test func histogramSumsToRatedSets() {
        let now = Date()
        let sets = [
            makeSet(rir: 0),
            makeSet(rir: 1),
            makeSet(rir: 2),
            makeSet(rpe: 7), // rir 3
            makeSet(rir: 5)  // rir 4+
        ]
        let session = makeSession(date: now, sets: sets)
        let histogram = EffortAnalyticsEngine.computeHistogram(from: [session], now: now)

        let totalInBins = histogram.reduce(0) { $0 + $1.count }
        #expect(totalInBins == 5)
        #expect(histogram[0].isHard == true)
        #expect(histogram[1].isHard == true)
        #expect(histogram[2].isHard == true)
        #expect(histogram[3].isHard == true)
        #expect(histogram[4].isHard == false)
    }
}
