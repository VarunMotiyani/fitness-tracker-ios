import Foundation
import SwiftData

@Model
final class AICallRecord {
    var timestamp: Date
    var callType: String
    var providerDisplayName: String
    var modelID: String
    var inputTokens: Int
    var outputTokens: Int
    var cachedTokens: Int
    var costUSD: Double
    var success: Bool
    var usedFallback: Bool

    init(callType: String, providerDisplayName: String, modelID: String,
         inputTokens: Int, outputTokens: Int, cachedTokens: Int,
         costUSD: Double, success: Bool, usedFallback: Bool) {
        self.timestamp = .now
        self.callType = callType
        self.providerDisplayName = providerDisplayName
        self.modelID = modelID
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.costUSD = costUSD
        self.success = success
        self.usedFallback = usedFallback
    }

    nonisolated static func cost(inputTokens: Int, outputTokens: Int, cachedTokens: Int,
                                 pricePerMTokIn: Double, pricePerMTokOut: Double,
                                 pricePerMTokCached: Double) -> Double {
        let raw = Double(inputTokens) / 1_000_000 * pricePerMTokIn
            + Double(outputTokens) / 1_000_000 * pricePerMTokOut
            + Double(cachedTokens) / 1_000_000 * pricePerMTokCached
        // Preserve the full estimate. Rounding each call to six decimal USD
        // places can turn legitimate low-volume usage into an exact zero
        // before the monthly total is calculated.
        return raw
    }

    /// Returns the stored charge when it is present, otherwise estimates a
    /// historical charge from the matching configured provider. Older builds
    /// persisted `costUSD == 0` when rates were not configured (or the active
    /// profile had not hydrated yet); the token counts are still enough to
    /// recover a useful estimate without mutating the ledger.
    static func billedCost(for record: AICallRecord, profiles: [ProviderProfile]) -> Double {
        guard record.costUSD == 0,
              record.inputTokens > 0 || record.outputTokens > 0 || record.cachedTokens > 0,
              record.modelID != "—" else { return record.costUSD }

        let exact = profiles.filter {
            $0.modelID == record.modelID && $0.displayName == record.providerDisplayName
        }
        let modelMatches = profiles.filter { $0.modelID == record.modelID }
        let profile: ProviderProfile?
        if exact.count == 1 {
            profile = exact[0]
        } else if exact.isEmpty, modelMatches.count == 1 {
            profile = modelMatches[0]
        } else {
            profile = nil
        }
        guard let profile else { return record.costUSD }
        return cost(inputTokens: record.inputTokens, outputTokens: record.outputTokens,
                    cachedTokens: record.cachedTokens,
                    pricePerMTokIn: profile.pricePerMTokIn,
                    pricePerMTokOut: profile.pricePerMTokOut,
                    pricePerMTokCached: profile.pricePerMTokCached)
    }
}
