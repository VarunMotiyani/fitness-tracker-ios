import Testing
import SwiftData
import Foundation
@testable import FitnessTracker

@MainActor
@Suite struct SessionModelsTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: CompletedSessionModel.self, CompletedEntryModel.self, LoggedSetModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func sessionWithEntriesAndSetsRoundTrips() throws {
        let ctx = ModelContext(try container())
        let s = CompletedSessionModel(startedAt: .init(timeIntervalSince1970: 0), weekdayRaw: 2,
            timeOfDayMinutes: 1080, plannedDurationMin: 60, energyRaw: "normal",
            timeAvailableMin: 60, plannedSessionID: nil)
        let e = CompletedEntryModel(exerciseID: "bench", performedOrder: 0)
        let set = LoggedSetModel(targetReps: 8, targetLoadKg: 60, actualReps: 8, actualLoadKg: 60,
            startedAt: .init(timeIntervalSince1970: 0), completedAt: .init(timeIntervalSince1970: 40),
            restBeforeSec: 120)
        e.sets.append(set); s.entries.append(e)
        ctx.insert(s)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<CompletedSessionModel>())
        #expect(fetched.count == 1)
        #expect(fetched[0].entries.first?.sets.first?.actualReps == 8)
        #expect(fetched[0].finishedAt == nil)
    }

    @Test func cascadeDeleteRemovesEntriesAndSets() throws {
        let ctx = ModelContext(try container())
        let s = CompletedSessionModel(startedAt: .now, weekdayRaw: 1, timeOfDayMinutes: 600,
            plannedDurationMin: 45, energyRaw: "beat", timeAvailableMin: 45, plannedSessionID: nil)
        let e = CompletedEntryModel(exerciseID: "squat", performedOrder: 0)
        e.sets.append(LoggedSetModel(targetReps: 5, targetLoadKg: 100, actualReps: 5,
            actualLoadKg: 100, startedAt: .now, completedAt: .now, restBeforeSec: 180))
        s.entries.append(e)
        ctx.insert(s); try ctx.save()
        ctx.delete(s); try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<LoggedSetModel>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<CompletedEntryModel>()).isEmpty)
    }
}
