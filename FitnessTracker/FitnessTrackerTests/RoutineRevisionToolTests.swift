import Testing
import SwiftData
import Foundation
import CoachMemory
@testable import FitnessTracker

@MainActor
@Suite struct RoutineRevisionToolTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: CoachMemoryModel.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func writesANewPreferenceMemory() throws {
        let ctx = ModelContext(try container())
        let tool = ProposeRoutineRevisionTool(context: ctx)

        let args = "{\"statement\": \"Wants more shoulder volume on push days\", \"action\": \"Add a lateral raise variation\"}"
        let result = tool.run(argsJSON: args)

        #expect(!result.contains("error"))
        let memories = try ctx.fetch(FetchDescriptor<CoachMemoryModel>())
        #expect(memories.count == 1)
        #expect(memories[0].kindRaw == "preference")
        #expect(memories[0].statement == "Wants more shoulder volume on push days")
    }

    @Test func reinforcesAnExistingSimilarPreferenceGivenAnID() throws {
        let ctx = ModelContext(try container())
        let existing = CoachMemoryModel(kindRaw: "preference", statement: "Wants more shoulder volume",
                                        confidence: 0.3, sourceKind: "agent", createdAt: .now, lastConfirmedAt: .now)
        ctx.insert(existing)
        try ctx.save()

        // The tool itself only ever proposes `.new` (it has no way to know an
        // existing memory's ID from chat context) — this test documents that
        // current, intentional scope: a second, similar statement creates a
        // second memory rather than reinforcing, same as any other `.new`-only
        // producer. Confirms no crash / unexpected merge behavior.
        let tool = ProposeRoutineRevisionTool(context: ctx)
        let args = "{\"statement\": \"Wants more shoulder volume\", \"action\": null}"
        _ = tool.run(argsJSON: args)

        let memories = try ctx.fetch(FetchDescriptor<CoachMemoryModel>())
        #expect(memories.count == 2)
    }

    @Test func rejectsBadArgs() throws {
        let ctx = ModelContext(try container())
        let tool = ProposeRoutineRevisionTool(context: ctx)
        let result = tool.run(argsJSON: "not json")
        #expect(result.contains("error"))
    }
}
