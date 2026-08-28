import Testing
import SwiftData
@testable import FitnessTracker

@MainActor
struct ProviderProfileTests {
    @Test func roundTripsAndExposesAdapterKind() throws {
        let container = try ModelContainer(for: ProviderProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        let p = ProviderProfile(displayName: "Local Ollama", adapterKind: .openAICompatible,
            baseURL: "http://localhost:11434/v1", modelID: "llama3.2",
            apiKeyRef: nil, supportsVision: false,
            pricePerMTokIn: 0, pricePerMTokOut: 0, pricePerMTokCached: 0)
        ctx.insert(p); try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<ProviderProfile>()).first
        #expect(fetched?.adapterKind == .openAICompatible)
        #expect(fetched?.baseURL == "http://localhost:11434/v1")
        #expect(fetched?.isActive == false)
    }

    @Test func unknownAdapterKindFallsBack() {
        let p = ProviderProfile(displayName: "x", adapterKind: .gemini, baseURL: nil,
            modelID: "m", apiKeyRef: nil, supportsVision: false,
            pricePerMTokIn: 0, pricePerMTokOut: 0, pricePerMTokCached: 0)
        p.adapterKindRaw = "nonsense"
        #expect(p.adapterKind == .appleOnDevice)
    }
}
