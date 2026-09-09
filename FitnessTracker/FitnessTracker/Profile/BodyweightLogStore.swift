import Foundation
import SwiftData
import Metrics

enum BodyweightReadingSlot: String, CaseIterable, Identifiable {
    case morning
    case night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: "Morning"
        case .night: "Night"
        }
    }
}

@MainActor
enum BodyweightLogStore {
    static let calendar = Calendar.appWeek

    /// Records or replaces one time-of-day reading. There can only be one
    /// `BodyweightEntryModel` per calendar day; its `kg` remains the reliable
    /// daily value consumed by every existing chart and metric.
    @discardableResult
    static func record(
        _ kg: Double,
        for slot: BodyweightReadingSlot,
        on date: Date = .now,
        in context: ModelContext
    ) throws -> BodyweightEntryModel {
        precondition(kg.isFinite && kg > 0, "Bodyweight must be a positive finite value")

        let entry = try entry(for: date, in: context) ?? BodyweightEntryModel(date: date, kg: kg)
        if entry.modelContext == nil { context.insert(entry) }

        switch slot {
        case .morning: entry.morningKg = kg
        case .night: entry.nightKg = kg
        }
        entry.kg = average(morning: entry.morningKg, night: entry.nightKg) ?? kg
        try context.save()
        return entry
    }

    /// Used by profile edits and imports that provide a single, undifferentiated
    /// measurement. It deliberately resets any same-day AM/PM pair so no stale
    /// reading can contaminate the displayed daily value.
    @discardableResult
    static func recordSingle(
        _ kg: Double,
        on date: Date = .now,
        in context: ModelContext
    ) throws -> BodyweightEntryModel {
        precondition(kg.isFinite && kg > 0, "Bodyweight must be a positive finite value")

        let entry = try entry(for: date, in: context) ?? BodyweightEntryModel(date: date, kg: kg)
        if entry.modelContext == nil { context.insert(entry) }
        entry.morningKg = nil
        entry.nightKg = nil
        entry.kg = kg
        try context.save()
        return entry
    }

    private static func entry(for date: Date, in context: ModelContext) throws -> BodyweightEntryModel? {
        try context.fetch(FetchDescriptor<BodyweightEntryModel>())
            .first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private static func average(morning: Double?, night: Double?) -> Double? {
        switch (morning, night) {
        case let (morning?, night?): (morning + night) / 2
        case let (morning?, nil): morning
        case let (nil, night?): night
        case (nil, nil): nil
        }
    }
}
