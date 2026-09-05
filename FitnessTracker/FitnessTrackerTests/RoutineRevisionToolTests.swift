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

    @Test func createsASeparateMemoryRatherThanReinforcingSinceTheToolOnlyEverProposesNew() throws {
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

    @Test func retiresTheLowestScoringExistingPreferenceOnceCapIsExceeded() throws {
        let ctx = ModelContext(try container())

        // 11 fresh, high-confidence preferences (recency weight ~1, score ~0.9)
        // plus 1 stale one (same confidence, but confirmed 90 days ago, so its
        // recency-decayed eviction score drops to ~0.9 * 0.125 = 0.1125) — well
        // below the new candidate's `newConfidence` score of 0.6 (score ~0.6,
        // since it's freshly written with recency weight ~1), so the stale one
        // is deterministically the lowest-ranked and the sole victim once the
        // 12-per-kind cap is exceeded by this tool's 13th write.
        let staleDate = Date.now.addingTimeInterval(-90 * 86_400)
        var staleID: UUID?
        for i in 0..<12 {
            let isStale = i == 0
            let model = CoachMemoryModel(kindRaw: "preference", statement: "Existing preference \(i)",
                                         confidence: 0.9, sourceKind: "agent", createdAt: .now,
                                         lastConfirmedAt: isStale ? staleDate : .now)
            if isStale { staleID = model.id }
            ctx.insert(model)
        }
        try ctx.save()

        let tool = ProposeRoutineRevisionTool(context: ctx)
        let args = "{\"statement\": \"Wants more shoulder volume on push days\", \"action\": null}"
        let result = tool.run(argsJSON: args)
        #expect(!result.contains("error"))

        let memories = try ctx.fetch(FetchDescriptor<CoachMemoryModel>())
        #expect(memories.count == 13)

        let livePreferences = memories.filter { $0.kindRaw == "preference" && !$0.retiredByCap }
        #expect(livePreferences.count == 12)

        let retired = memories.filter { $0.retiredByCap }
        #expect(retired.count == 1)
        #expect(retired.first?.id == staleID)
    }

    /// The seam-level regression test for Critical #1: writes a preference through
    /// the tool, then replicates exactly what `PlanGeneration.generateAndStore` does
    /// before every plan-generation call — re-fetch `CoachMemoryModel`, map to domain,
    /// `MemoryRecall.select(from:context:now:)` — and asserts the statement actually
    /// surfaces in `recalled.digest`. Before the fix (tool wrote at confidence 0.3),
    /// this would fail: `digest` drops anything under 0.6, so `recalled.digest` would
    /// come back empty and this statement would never appear in it.
    @Test func writtenPreferenceReachesTheNextPlanGenerationDigest() throws {
        let ctx = ModelContext(try container())
        let tool = ProposeRoutineRevisionTool(context: ctx)

        let args = "{\"statement\": \"Wants more shoulder volume on push days\", \"action\": \"Add a lateral raise variation\"}"
        let result = tool.run(argsJSON: args)
        #expect(!result.contains("error"))

        let existingMemories = ((try? ctx.fetch(FetchDescriptor<CoachMemoryModel>())) ?? []).map { $0.toDomain() }
        let recalled = MemoryRecall.select(from: existingMemories, context: RecallContext(), now: .now)

        #expect(recalled.digest.contains("Wants more shoulder volume on push days"))
    }

    @Test func rejectsBadArgs() throws {
        let ctx = ModelContext(try container())
        let tool = ProposeRoutineRevisionTool(context: ctx)
        let result = tool.run(argsJSON: "not json")
        #expect(result.contains("error"))
    }
}
