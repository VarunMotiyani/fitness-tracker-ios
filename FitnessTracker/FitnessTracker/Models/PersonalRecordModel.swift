import Foundation
import SwiftData

/// A personal record. `typeRaw` is the raw value of the PR-type enum; all other
/// enum-typed concepts are likewise stored as raw columns.
@Model
final class PersonalRecordModel {
    var typeRaw: String
    var exerciseID: String
    var value: Double
    var atLoadKg: Double
    var reps: Int
    var date: Date
    var sessionID: UUID

    init(typeRaw: String, exerciseID: String, value: Double, atLoadKg: Double,
         reps: Int, date: Date, sessionID: UUID) {
        self.typeRaw = typeRaw
        self.exerciseID = exerciseID
        self.value = value
        self.atLoadKg = atLoadKg
        self.reps = reps
        self.date = date
        self.sessionID = sessionID
    }
}
