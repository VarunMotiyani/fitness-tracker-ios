public struct RawFreeExerciseDBExercise: Decodable, Sendable {
    public let id: String?
    public let name: String
    public let force: String?
    public let level: String
    public let mechanic: String?
    public let equipment: String?
    public let primaryMuscles: [String]
    public let secondaryMuscles: [String]
    public let instructions: [String]
    public let category: String
    public let images: [String]
}
