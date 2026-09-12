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

    @Test func preservesMicroscopicButNonzeroUsageCost() {
        let c = AICallRecord.cost(inputTokens: 1, outputTokens: 0, cachedTokens: 0,
                                  pricePerMTokIn: 0.10, pricePerMTokOut: 0, pricePerMTokCached: 0)
        #expect(c > 0)
    }

    @Test func reestimatesHistoricalZeroFromMatchingProfile() {
        let profile = ProviderProfile(displayName: "Gemini", adapterKind: .gemini,
                                      baseURL: nil, modelID: "gemini-3.8-flash",
                                      apiKeyRef: nil, supportsVision: true,
                                      pricePerMTokIn: 0.10, pricePerMTokOut: 0.40,
                                      pricePerMTokCached: 0)
        let record = AICallRecord(callType: "askCoach", providerDisplayName: "Gemini",
                                  modelID: "gemini-3.8-flash", inputTokens: 10_000,
                                  outputTokens: 2_000, cachedTokens: 0, costUSD: 0,
                                  success: true, usedFallback: false)
        let estimated = AICallRecord.billedCost(for: record, profiles: [profile])
        #expect(abs(estimated - 0.0018) < 1e-9)
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
