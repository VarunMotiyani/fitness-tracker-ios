import Foundation
import SwiftData

nonisolated enum AdapterKind: String, Codable, Sendable, CaseIterable {
    case openAICompatible
    case gemini
    case appleOnDevice
}

@Model
final class ProviderProfile {
    var displayName: String
    var adapterKindRaw: String
    var baseURL: String?
    var modelID: String
    var apiKeyRef: String?
    var supportsVision: Bool
    var pricePerMTokIn: Double
    var pricePerMTokOut: Double
    var pricePerMTokCached: Double
    var isActive: Bool
    var createdAt: Date

    var adapterKind: AdapterKind { AdapterKind(rawValue: adapterKindRaw) ?? .appleOnDevice }

    init(displayName: String,
         adapterKind: AdapterKind,
         baseURL: String?,
         modelID: String,
         apiKeyRef: String?,
         supportsVision: Bool,
         pricePerMTokIn: Double,
         pricePerMTokOut: Double,
         pricePerMTokCached: Double) {
        self.displayName = displayName
        self.adapterKindRaw = adapterKind.rawValue
        self.baseURL = baseURL
        self.modelID = modelID
        self.apiKeyRef = apiKeyRef
        self.supportsVision = supportsVision
        self.pricePerMTokIn = pricePerMTokIn
        self.pricePerMTokOut = pricePerMTokOut
        self.pricePerMTokCached = pricePerMTokCached
        self.isActive = false
        self.createdAt = .now
    }
}
