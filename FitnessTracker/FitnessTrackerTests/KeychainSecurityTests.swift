import Testing
import Foundation
import SwiftData
@testable import FitnessTracker

@MainActor
struct KeychainSecurityTests {
    /// The branch's headline security property: the API key itself never reaches
    /// SwiftData — only the opaque `apiKeyRef` UUID does.
    @Test func apiKeyNeverLandsInSwiftData() throws {
        let key = "sk-secret-\(UUID().uuidString)"
        let ref = UUID().uuidString
        try KeychainStore.set(key, account: ref)
        defer { try? KeychainStore.delete(account: ref) }

        let container = try ModelContainer(for: ProviderProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext

        let profile = ProviderProfile(displayName: "Secure", adapterKind: .gemini,
            baseURL: nil, modelID: "gemini-x", apiKeyRef: ref, supportsVision: false,
            pricePerMTokIn: 0, pricePerMTokOut: 0, pricePerMTokCached: 0)
        ctx.insert(profile)
        try ctx.save()

        let fetched = try #require(try ctx.fetch(FetchDescriptor<ProviderProfile>()).first)

        let storedStrings: [String?] = [
            fetched.displayName, fetched.baseURL, fetched.modelID, fetched.apiKeyRef,
        ]
        #expect(!storedStrings.compactMap { $0 }.contains(key))
        #expect(fetched.apiKeyRef == ref)          // only the opaque UUID persisted
        #expect(fetched.apiKeyRef != key)
        // and the key is still retrievable from the Keychain by that ref
        #expect(try KeychainStore.get(account: ref) == key)
    }
}
