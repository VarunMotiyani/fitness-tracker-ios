import Foundation
import SwiftData

/// The onboarding answers, persisted. One instance per install.
///
/// Enum-typed fields (goal, experience, equipment, muscles) are stored as their
/// `rawValue` strings and mapped back to `FitnessCore` value types in
/// `UserProfile+Mapping.swift`.
@Model
final class UserProfile {
    var goalRaw: String
    var experienceRaw: String
    var heightCm: Double
    var weightKg: Double
    var birthYear: Int
    var sexRaw: String
    var sessionsPerWeek: Int
    var sessionLengthMinutes: Int
    var availableEquipmentRaws: [String]
    var excludedMuscleRaws: [String]
    var excludedExerciseIDs: [String]
    var createdAt: Date
    var updatedAt: Date

    init(goalRaw: String,
         experienceRaw: String,
         heightCm: Double,
         weightKg: Double,
         birthYear: Int,
         sexRaw: String,
         sessionsPerWeek: Int,
         sessionLengthMinutes: Int,
         availableEquipmentRaws: [String],
         excludedMuscleRaws: [String],
         excludedExerciseIDs: [String]) {
        self.goalRaw = goalRaw
        self.experienceRaw = experienceRaw
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.birthYear = birthYear
        self.sexRaw = sexRaw
        self.sessionsPerWeek = sessionsPerWeek
        self.sessionLengthMinutes = sessionLengthMinutes
        self.availableEquipmentRaws = availableEquipmentRaws
        self.excludedMuscleRaws = excludedMuscleRaws
        self.excludedExerciseIDs = excludedExerciseIDs
        self.createdAt = .now
        self.updatedAt = .now
    }
}
