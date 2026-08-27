import Foundation

public struct JSONSchema: Sendable, Equatable {
    public let json: String
    public init(json: String) { self.json = json }
}

public struct ImagePayload: Sendable, Equatable {
    public let data: Data
    public let mimeType: String
    public init(data: Data, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
}
