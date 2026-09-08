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
            let entries = try context.fetch(FetchDescriptor<BodyweightEntryModel>())
            if let entry = entries.first(where: { Calendar.isoUTC.isDate($0.date, inSameDayAs: now) }) {
                entry.kg = draft.weightKg
            } else {
                context.insert(BodyweightEntryModel(date: now, kg: draft.weightKg))
            }
        }
        try context.save()
    }
}
