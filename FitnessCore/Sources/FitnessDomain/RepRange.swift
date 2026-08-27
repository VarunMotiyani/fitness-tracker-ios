public struct RepRange: Codable, Sendable, Equatable {
    public let min: Int
    public let max: Int
    public init(min: Int, max: Int) {
        self.min = min
        self.max = max
    }
}
