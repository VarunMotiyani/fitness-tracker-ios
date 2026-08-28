import Foundation
import Testing
@testable import FitnessTracker

struct KeychainStoreTests {
    @Test func setGetDeleteRoundTrip() throws {
        let account = "test-\(UUID().uuidString)"
        defer { try? KeychainStore.delete(account: account) }

        #expect(try KeychainStore.get(account: account) == nil)
        try KeychainStore.set("sk-abc123", account: account)
        #expect(try KeychainStore.get(account: account) == "sk-abc123")
        try KeychainStore.set("sk-xyz789", account: account)          // overwrite
        #expect(try KeychainStore.get(account: account) == "sk-xyz789")
        try KeychainStore.delete(account: account)
        #expect(try KeychainStore.get(account: account) == nil)
    }
}
