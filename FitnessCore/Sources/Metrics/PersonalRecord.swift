import Foundation

public enum PRType: String, Codable, Sendable, CaseIterable {
    case heaviestWeight
    case repsAtWeight
    case estimated1RM
}

public struct PersonalRecord: Sendable, Codable, Equatable {
    public let type: PRType
    public let exerciseID: String
    public let value: Double
    public let atLoadKg: Double
    public let reps: Int
    public let date: Date
    public let sessionID: UUID

    public init(
        type: PRType,
        exerciseID: String,
        value: Double,
        atLoadKg: Double,
        reps: Int,
        date: Date,
        sessionID: UUID
    ) {
        self.type = type
        self.exerciseID = exerciseID
        self.value = value
        self.atLoadKg = atLoadKg
        self.reps = reps
        self.date = date
        self.sessionID = sessionID
    }
}
