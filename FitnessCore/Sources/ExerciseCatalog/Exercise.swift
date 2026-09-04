import FitnessDomain

public struct Exercise: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let primaryMuscle: MuscleGroup
    public let secondaryMuscles: [MuscleGroup]
    public let equipment: Equipment
    public let mechanic: Mechanic
    public let force: ForceType?
    public let difficulty: Difficulty
    public let isUnilateral: Bool
    public let instructions: [String]
    public let imagePaths: [String]

    public init(id: String, name: String, primaryMuscle: MuscleGroup,
                secondaryMuscles: [MuscleGroup], equipment: Equipment,
                mechanic: Mechanic, force: ForceType?, difficulty: Difficulty,
                isUnilateral: Bool, instructions: [String], imagePaths: [String]) {
        self.id = id
        self.name = name
        self.primaryMuscle = primaryMuscle
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.mechanic = mechanic
        self.force = force
        self.difficulty = difficulty
        self.isUnilateral = isUnilateral
        self.instructions = instructions
        self.imagePaths = imagePaths
    }

    /// The animated-demo path in `imagePaths`, if the catalog entry has one (a static
    /// thumbnail and a `.gif` demo are both listed for most bundled exercises; custom,
    /// user-created exercises have neither).
    public var gifImagePath: String? {
        imagePaths.first { $0.lowercased().hasSuffix(".gif") }
    }
}
