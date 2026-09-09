import Foundation
import SwiftData
import Metrics

enum AthleteProfileStoreError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        }
    }
}

@MainActor
enum AthleteProfileStore {
    /// Applies all profile fields together. A changed manual weight is recorded
    /// in the existing timeline, merging with a same-day entry rather than
    /// creating duplicate readings from repeated edits.
    static func apply(_ draft: AthleteProfileDraft,
                      to profile: UserProfile,
                      in context: ModelContext,
                      now: Date = .now) throws {
        if let error = draft.validationError { throw AthleteProfileStoreError.invalid(error) }
        let weightChanged = profile.weightKg != draft.weightKg

        profile.goalRaw = draft.goalRaw
        profile.experienceRaw = draft.experienceRaw
        profile.heightCm = draft.heightCm
        profile.weightKg = draft.weightKg
        profile.birthYear = draft.birthYear
        profile.sexRaw = draft.sexRaw
        profile.sessionsPerWeek = draft.sessionsPerWeek
        profile.sessionLengthMinutes = draft.sessionLengthMinutes
        profile.availableEquipmentRaws = draft.availableEquipmentRaws
        profile.excludedMuscleRaws = draft.excludedMuscleRaws
        profile.excludedExerciseIDs = draft.excludedExerciseIDs
        profile.bodyFatPercent = draft.bodyFatPercent
        profile.skeletalMuscleMassKg = draft.skeletalMuscleMassKg
        profile.bodyFatMassKg = draft.bodyFatMassKg
        profile.fatFreeMassKg = draft.fatFreeMassKg
        profile.totalBodyWaterL = draft.totalBodyWaterL
        profile.proteinKg = draft.proteinKg
        profile.mineralKg = draft.mineralKg
        profile.basalMetabolicRateKcal = draft.basalMetabolicRateKcal
        profile.visceralFatLevel = draft.visceralFatLevel
        profile.inBodyScore = draft.inBodyScore
        profile.waistHipRatio = draft.waistHipRatio
        profile.phaseAngleDegrees = draft.phaseAngleDegrees
        profile.updatedAt = now

        if weightChanged {
            // A profile edit is a generic daily value, rather than an AM or PM
            // measurement. Keeping it in the same store prevents duplicate
            // calendar-day records and keeps charts on their daily metric.
            _ = try BodyweightLogStore.recordSingle(draft.weightKg, on: now, in: context)
        }
        try context.save()
    }
}
