import Foundation
import SwiftData
import Testing
import Metrics
@testable import FitnessTracker

@MainActor
struct BodyweightLogStoreTests {
    private let calendar = Calendar.appWeek

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(calendar: calendar, year: 2026, month: 9, day: day, hour: 12))!
    }

    private func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: BodyweightEntryModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func morningAndNightReadingsShareOneDailyAverage() throws {
        let context = try context()
        let day = date(9)

        _ = try BodyweightLogStore.record(74.2, for: .morning, on: day, in: context)
        let entry = try BodyweightLogStore.record(75.0, for: .night, on: day, in: context)

        #expect(entry.morningKg == 74.2)
        #expect(entry.nightKg == 75.0)
        #expect(entry.kg == 74.6)
        #expect(try context.fetch(FetchDescriptor<BodyweightEntryModel>()).count == 1)
    }

    @Test func replacingOneReadingRecalculatesTheDailyAverage() throws {
        let context = try context()
        let day = date(9)
        _ = try BodyweightLogStore.record(74.2, for: .morning, on: day, in: context)
        _ = try BodyweightLogStore.record(75.0, for: .night, on: day, in: context)

        let entry = try BodyweightLogStore.record(74.6, for: .morning, on: day, in: context)

        #expect(entry.morningKg == 74.6)
        #expect(entry.nightKg == 75.0)
        #expect(entry.kg == 74.8)
    }

    @Test func aSingleReadingRemainsTheDailyWeight() throws {
        let context = try context()

        let entry = try BodyweightLogStore.record(74.2, for: .morning, on: date(9), in: context)

        #expect(entry.kg == 74.2)
        #expect(entry.nightKg == nil)
    }

    @Test func aGenericDailyImportReplacesTheDayRatherThanAddingAnotherRecord() throws {
        let context = try context()
        let day = date(9)
        _ = try BodyweightLogStore.record(74.2, for: .morning, on: day, in: context)
        _ = try BodyweightLogStore.record(75.0, for: .night, on: day, in: context)

        let entry = try BodyweightLogStore.recordSingle(74.6, on: day, in: context)

        #expect(entry.kg == 74.6)
        #expect(entry.morningKg == nil)
        #expect(entry.nightKg == nil)
        #expect(try context.fetch(FetchDescriptor<BodyweightEntryModel>()).count == 1)
    }
}
