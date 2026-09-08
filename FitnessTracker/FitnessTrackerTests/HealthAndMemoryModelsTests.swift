import Testing
import SwiftData
import Foundation
import Metrics
@testable import FitnessTracker

@MainActor
@Suite struct HealthAndMemoryModelsTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: BodyweightEntryModel.self, DailyCheckinModel.self, ObservationModel.self,
            PersonalRecordModel.self, CoachMemoryModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func allFiveModelsRoundTrip() throws {
        let ctx = ModelContext(try container())

        let bw = BodyweightEntryModel(date: .init(timeIntervalSince1970: 0), kg: 82.5)
        let checkin = DailyCheckinModel(date: .init(timeIntervalSince1970: 100))
        checkin.sleepQuality = 4
        let obs = ObservationModel(kind: "e1rm", value: 120.0, unit: "kg",
            timestamp: .init(timeIntervalSince1970: 200))
        let pr = PersonalRecordModel(typeRaw: "e1rm", exerciseID: "bench", value: 130.0,
            atLoadKg: 110.0, reps: 3, date: .init(timeIntervalSince1970: 300), sessionID: UUID())

        ctx.insert(bw); ctx.insert(checkin); ctx.insert(obs); ctx.insert(pr)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<BodyweightEntryModel>()).first?.kg == 82.5)
        #expect(try ctx.fetch(FetchDescriptor<DailyCheckinModel>()).first?.sleepQuality == 4)
        let fetchedObs = try ctx.fetch(FetchDescriptor<ObservationModel>()).first
        #expect(fetchedObs?.value == 120.0)
        #expect(fetchedObs?.contextJSON == "{}")
        #expect(try ctx.fetch(FetchDescriptor<PersonalRecordModel>()).first?.reps == 3)
    }

    @Test func coachMemoryStoresFlatSourceAndSupersededBy() throws {
        let ctx = ModelContext(try container())
        let superseder = UUID()

        let mem = CoachMemoryModel(kindRaw: "progressionRule", statement: "Bench adds 2.5kg weekly",
            confidence: 0.8, sourceKind: "agent",
            createdAt: .init(timeIntervalSince1970: 0), lastConfirmedAt: .init(timeIntervalSince1970: 0))
        mem.sourceAgent = "memoryKeeper"
        mem.supersededBy = superseder
        ctx.insert(mem)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<CoachMemoryModel>()).first
        #expect(fetched?.sourceKind == "agent")
        #expect(fetched?.sourceAgent == "memoryKeeper")
        #expect(fetched?.supersededBy == superseder)
        #expect(fetched?.action == nil)
        #expect(fetched?.retiredByCap == false)
        #expect(fetched?.tagFreeJSON == "[]")
    }

    @Test func observationConfirmedDefaultsTrue() {
        let obs = ObservationModel(kind: "bodyweight", value: 80, unit: "kg", timestamp: Date())
        #expect(obs.confirmed)
    }

    @Test func dailyCheckinDateFilteringForTodayAndPast() throws {
        let ctx = ModelContext(try container())
        let cal = Calendar.isoUTC
        let now = Date()
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: now) else { return }

        let pastCheckin = DailyCheckinModel(date: yesterday)
        pastCheckin.sleepQuality = 6
        pastCheckin.soreness = 5
        ctx.insert(pastCheckin)
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<DailyCheckinModel>())
        // Today's checkin should be nil before today is logged
        let todayCheckinBefore = all.first { cal.isDate($0.date, inSameDayAs: now) }
        #expect(todayCheckinBefore == nil)

        // Yesterday's checkin should be found by yesterday's date
        let yesterdayCheckin = all.first { cal.isDate($0.date, inSameDayAs: yesterday) }
        #expect(yesterdayCheckin != nil)
        #expect(yesterdayCheckin?.sleepQuality == 6)

        // Log today's checkin
        let todayCheckin = DailyCheckinModel(date: now)
        todayCheckin.sleepQuality = 8
        todayCheckin.soreness = 2
        todayCheckin.note = "Feeling great"
        ctx.insert(todayCheckin)
        try ctx.save()

        let allAfter = try ctx.fetch(FetchDescriptor<DailyCheckinModel>())
        let todayCheckinAfter = allAfter.first { cal.isDate($0.date, inSameDayAs: now) }
        #expect(todayCheckinAfter != nil)
        #expect(todayCheckinAfter?.sleepQuality == 8)
        #expect(todayCheckinAfter?.soreness == 2)
        #expect(todayCheckinAfter?.note == "Feeling great")
    }
}
