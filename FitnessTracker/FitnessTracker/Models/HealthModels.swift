import Foundation
import SwiftData

/// A single bodyweight measurement.
@Model
final class BodyweightEntryModel {
    var date: Date
    var kg: Double

    init(date: Date, kg: Double) {
        self.date = date
        self.kg = kg
    }
}

/// A daily subjective check-in. All ratings are optional and stored as raw `Int`s.
@Model
final class DailyCheckinModel {
    var date: Date
    var sleepQuality: Int?
    var soreness: Int?
    var note: String?

    init(date: Date) {
        self.date = date
        self.sleepQuality = nil
        self.soreness = nil
        self.note = nil
    }
}

/// A derived metric observation. `contextJSON` holds the `[String: String]` context
/// encoded as a JSON object string (default `"{}"`). Every enum-typed concept is a raw `String`.
@Model
final class ObservationModel {
    var kind: String
    var value: Double
    var unit: String
    var timestamp: Date
    var contextJSON: String
    var sessionID: UUID?
    var entryExerciseID: String?
    /// `false` only for AI-derived rows awaiting your confirmation (design
    /// spec §6) — every manually-entered or deterministically-computed
    /// observation is confirmed by construction.
    var confirmed: Bool = true

    init(kind: String, value: Double, unit: String, timestamp: Date) {
        self.kind = kind
        self.value = value
        self.unit = unit
        self.timestamp = timestamp
        self.contextJSON = "{}"
        self.sessionID = nil
        self.entryExerciseID = nil
        self.confirmed = true
    }
}
