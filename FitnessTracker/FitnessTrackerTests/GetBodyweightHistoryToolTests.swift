import Testing
import SwiftData
import Foundation
@testable import FitnessTracker

/// Found live on-device: asked "what's my latest weight" seconds after
/// successfully logging one, the coach answered "no bodyweight logs on
/// record" — its self-authored `query_training_data` JMESPath apparently
/// failed and got papered over. This tool removes that failure class: no
/// query for the model to get wrong, just a direct, deterministic read.
@MainActor
@Suite struct GetBodyweightHistoryToolTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: BodyweightEntryModel.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func returnsEntriesMostRecentFirst() throws {
        let ctx = ModelContext(try container())
        ctx.insert(BodyweightEntryModel(date: Date(timeIntervalSinceNow: -86400 * 2), kg: 78.4))
        ctx.insert(BodyweightEntryModel(date: Date(timeIntervalSinceNow: -86400), kg: 76.0))
        ctx.insert(BodyweightEntryModel(date: .now, kg: 74.0))
        try ctx.save()

        let result = GetBodyweightHistoryTool(context: ctx).run(argsJSON: "{}")
        let json = try JSONSerialization.jsonObject(with: Data(result.utf8)) as! [String: Any]
        let entries = json["entries"] as! [[String: Any]]

        #expect(entries.count == 3)
        #expect(entries.first?["kg"] as? Double == 74.0)
        #expect(entries.last?["kg"] as? Double == 78.4)
    }

    @Test func emptyHistoryReturnsAClearNoteRatherThanAnError() throws {
        let ctx = ModelContext(try container())

        let result = GetBodyweightHistoryTool(context: ctx).run(argsJSON: "{}")

        #expect(!result.contains("error"))
        #expect(result.contains("no bodyweight logged yet"))
    }
}
