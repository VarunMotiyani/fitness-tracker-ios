import Foundation
import SwiftData

nonisolated enum AdapterKind: String, Codable, Sendable, CaseIterable {
    case openAICompatible
    case gemini
    case appleOnDevice
    /// Google Cloud Vertex AI — Gemini models via a GCP project/location
    /// endpoint, authenticated with an OAuth2 bearer token instead of a
    /// simple API key. `baseURL` holds the full path up to and including
    /// `.../publishers/google/models/` (the user's project + location), the
    /// same "paste your endpoint" pattern as `openAICompatible`; `apiKeyRef`
    /// holds the bearer token (e.g. from `gcloud auth print-access-token`).
    case vertexAI
    /// AWS Bedrock — `apiKeyRef` holds a JSON string
    /// `{"accessKeyId":"...","secretAccessKey":"...","sessionToken":"..."}`
    /// (sessionToken optional); `baseURL` holds the AWS region (e.g.
    /// `"us-east-1"`), not a URL — the endpoint is derived from it.
    case bedrock
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
