import Testing
import Foundation
import SwiftData
@testable import FitnessTracker

@MainActor
struct AICallRecordTests {
    @Test func costMath() {
        let c = AICallRecord.cost(inputTokens: 500_000, outputTokens: 100_000, cachedTokens: 0,
                                  pricePerMTokIn: 0.30, pricePerMTokOut: 2.50, pricePerMTokCached: 0)
        #expect(abs(c - (0.15 + 0.25)) < 1e-9)
    }

    @Test func persists() throws {
        let container = try ModelContainer(for: AICallRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let r = AICallRecord(callType: "weeklyPlan", providerDisplayName: "P", modelID: "m",
                             inputTokens: 10, outputTokens: 20, cachedTokens: 0,
                             costUSD: 0.0001, success: true, usedFallback: false)
        container.mainContext.insert(r)
        try container.mainContext.save()
        #expect(try container.mainContext.fetch(FetchDescriptor<AICallRecord>()).count == 1)
    }
}
