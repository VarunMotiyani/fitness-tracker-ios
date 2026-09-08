import Foundation

/// An editable, value-typed copy of the single persisted athlete profile.
/// Keeping validation here lets SwiftUI forms remain simple and gives future
/// InBody confirmation the exact same write contract.
struct AthleteProfileDraft: Equatable {
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

    init(profile: UserProfile) {
        goalRaw = profile.goalRaw
        experienceRaw = profile.experienceRaw
        heightCm = profile.heightCm
        weightKg = profile.weightKg
        birthYear = profile.birthYear
        sexRaw = profile.sexRaw
        sessionsPerWeek = profile.sessionsPerWeek
        sessionLengthMinutes = profile.sessionLengthMinutes
        availableEquipmentRaws = profile.availableEquipmentRaws
        excludedMuscleRaws = profile.excludedMuscleRaws
        excludedExerciseIDs = profile.excludedExerciseIDs
        bodyFatPercent = profile.bodyFatPercent
        skeletalMuscleMassKg = profile.skeletalMuscleMassKg
        bodyFatMassKg = profile.bodyFatMassKg
        fatFreeMassKg = profile.fatFreeMassKg
        totalBodyWaterL = profile.totalBodyWaterL
        proteinKg = profile.proteinKg
        mineralKg = profile.mineralKg
        basalMetabolicRateKcal = profile.basalMetabolicRateKcal
        visceralFatLevel = profile.visceralFatLevel
        inBodyScore = profile.inBodyScore
        waistHipRatio = profile.waistHipRatio
        phaseAngleDegrees = profile.phaseAngleDegrees
    }

    var validationError: String? {
        guard heightCm.isFinite, heightCm > 0 else { return "Height must be greater than zero." }
        guard weightKg.isFinite, weightKg > 0 else { return "Weight must be greater than zero." }
        guard birthYear >= 1900 else { return "Select a valid birth year." }
        guard (2...7).contains(sessionsPerWeek) else { return "Sessions per week must be between 2 and 7." }
        guard [30, 45, 60, 90].contains(sessionLengthMinutes) else { return "Choose a supported session length." }
        guard validPercentage(bodyFatPercent) else { return "Body fat must be between 0% and 100%." }

        for (value, label) in [
            (skeletalMuscleMassKg, "Skeletal muscle mass"),
            (bodyFatMassKg, "Body fat mass"),
            (fatFreeMassKg, "Fat-free mass"),
            (totalBodyWaterL, "Total body water"),
            (proteinKg, "Protein"),
            (mineralKg, "Minerals"),
            (basalMetabolicRateKcal, "Basal metabolic rate"),
            (visceralFatLevel, "Visceral fat level"),
            (inBodyScore, "InBody score"),
        ] {
            if let value, (!value.isFinite || value < 0) {
                return "\(label) cannot be negative."
            }
        }

        for (value, label) in [(waistHipRatio, "Waist–hip ratio"), (phaseAngleDegrees, "Phase angle")] {
            if let value, (!value.isFinite || value <= 0) {
                return "\(label) must be greater than zero."
            }
        }
        return nil
    }

    func changesPlanInput(comparedTo profile: UserProfile) -> Bool {
        goalRaw != profile.goalRaw
            || experienceRaw != profile.experienceRaw
            || sessionsPerWeek != profile.sessionsPerWeek
            || sessionLengthMinutes != profile.sessionLengthMinutes
            || Set(availableEquipmentRaws) != Set(profile.availableEquipmentRaws)
            || Set(excludedMuscleRaws) != Set(profile.excludedMuscleRaws)
            || Set(excludedExerciseIDs) != Set(profile.excludedExerciseIDs)
    }

    private func validPercentage(_ value: Double?) -> Bool {
        guard let value else { return true }
        return value.isFinite && (0...100).contains(value)
    }
}
