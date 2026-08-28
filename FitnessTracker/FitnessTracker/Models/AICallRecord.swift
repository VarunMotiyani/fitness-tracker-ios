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
        return (raw * 1_000_000).rounded() / 1_000_000
    }
}
