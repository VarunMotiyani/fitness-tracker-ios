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
    /// Nil means the planner chooses a sensible style from days and experience.
    /// Stored as a string to keep SwiftData migrations lightweight.
    var splitTemplateName: String?
    var sessionLengthMinutes: Int
    var availableEquipmentRaws: [String]
    var excludedMuscleRaws: [String]
    var excludedExerciseIDs: [String]
    // Current body-composition snapshot. All fields are optional because an
    // athlete can build their profile before they have an InBody reading. A
    // later confirmed scan will update these same values.
    var bodyFatPercent: Double?
    var skeletalMuscleMassKg: Double?
    var bodyFatMassKg: Double?
    var fatFreeMassKg: Double?
    var totalBodyWaterL: Double?
    var proteinKg: Double?
    var mineralKg: Double?
    var basalMetabolicRateKcal: Double?
    var visceralFatLevel: Double?
    var inBodyScore: Double?
    var waistHipRatio: Double?
    var phaseAngleDegrees: Double?
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
        self.splitTemplateName = nil
        self.sessionLengthMinutes = sessionLengthMinutes
        self.availableEquipmentRaws = availableEquipmentRaws
        self.excludedMuscleRaws = excludedMuscleRaws
        self.excludedExerciseIDs = excludedExerciseIDs
        self.bodyFatPercent = nil
        self.skeletalMuscleMassKg = nil
        self.bodyFatMassKg = nil
        self.fatFreeMassKg = nil
        self.totalBodyWaterL = nil
        self.proteinKg = nil
        self.mineralKg = nil
        self.basalMetabolicRateKcal = nil
        self.visceralFatLevel = nil
        self.inBodyScore = nil
        self.waistHipRatio = nil
        self.phaseAngleDegrees = nil
        self.createdAt = .now
        self.updatedAt = .now
    }
}
