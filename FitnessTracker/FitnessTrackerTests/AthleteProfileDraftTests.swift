import Testing
import SwiftData
import Foundation
import FitnessDomain
@testable import FitnessTracker

@MainActor
@Suite struct AthleteProfileDraftTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: UserProfile.self, BodyweightEntryModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func profile(weightKg: Double = 75) -> UserProfile {
        UserProfile(
            goalRaw: "buildMuscle", experienceRaw: "intermediate",
            heightCm: 175, weightKg: weightKg, birthYear: 2000, sexRaw: "male",
            sessionsPerWeek: 4, sessionLengthMinutes: 60,
            availableEquipmentRaws: ["barbell", "dumbbell"],
            excludedMuscleRaws: [], excludedExerciseIDs: []
        )
    }

    @Test func appliesPlanningChangesAndWritesChangedWeightToTimeline() throws {
        let container = try container()
        let context = container.mainContext
        let athlete = profile()
        context.insert(athlete)
        var draft = AthleteProfileDraft(profile: athlete)
        draft.goalRaw = "loseFat"
        draft.sessionsPerWeek = 5
        draft.weightKg = 74.6

        #expect(draft.changesPlanInput(comparedTo: athlete))
        try AthleteProfileStore.apply(
            draft, to: athlete, in: context,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(athlete.makeUserContext().goal == .loseFat)
        #expect(athlete.makeUserContext().sessionsPerWeek == 5)
        #expect(try context.fetch(FetchDescriptor<BodyweightEntryModel>()).map(\.kg) == [74.6])
    }

    @Test func rejectsInvalidBodyCompositionValues() {
        var draft = AthleteProfileDraft(profile: profile())
        draft.bodyFatPercent = 101
        #expect(draft.validationError == "Body fat must be between 0% and 100%.")

        draft.bodyFatPercent = 18
        draft.skeletalMuscleMassKg = -1
        #expect(draft.validationError == "Skeletal muscle mass cannot be negative.")
    }

    @Test func savesUnchangedWeightWithoutAddingTimelineEntry() throws {
        let container = try container()
        let context = container.mainContext
        let athlete = profile()
        context.insert(athlete)
        var draft = AthleteProfileDraft(profile: athlete)
        draft.bodyFatPercent = 18.2

        try AthleteProfileStore.apply(draft, to: athlete, in: context)

        #expect(try context.fetch(FetchDescriptor<BodyweightEntryModel>()).isEmpty)
        #expect(athlete.bodyFatPercent == 18.2)
    }
}
