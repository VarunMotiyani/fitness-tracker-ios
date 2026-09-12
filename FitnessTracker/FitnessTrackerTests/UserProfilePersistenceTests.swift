import Testing
import SwiftData
import Foundation
@testable import FitnessTracker

@MainActor
struct UserProfilePersistenceTests {

    @Test func startupUsesPersistedProfileInsteadOfSeedingAgain() throws {
        let container = try ModelContainer(
            for: UserProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profile = UserProfile(
            goalRaw: "buildMuscle", experienceRaw: "advanced",
            heightCm: 180, weightKg: 82, birthYear: 1990, sexRaw: "male",
            sessionsPerWeek: 5, sessionLengthMinutes: 75,
            availableEquipmentRaws: ["barbell"], excludedMuscleRaws: [], excludedExerciseIDs: []
        )
        context.insert(profile)
        try context.save()

        #expect(AppBootstrap.existingUserProfile(in: context)?.id == profile.id)
        #expect(AppBootstrap.needsInitialSeed(in: context) == false)
    }

    @Test func targetWeightRoundTripsAcrossViewLifetimes() {
        let suiteName = "UserProfilePersistenceTests.targetWeight"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        TargetWeightStore.save(82.5, to: defaults)
        #expect(TargetWeightStore.load(from: defaults) == 82.5)

        TargetWeightStore.save(nil, to: defaults)
        #expect(TargetWeightStore.load(from: defaults) == nil)
    }

    @Test func roundTripsThroughSwiftData() throws {
        let container = try ModelContainer(
            for: UserProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let profile = UserProfile(
            goalRaw: "buildMuscle", experienceRaw: "intermediate",
            heightCm: 178, weightKg: 76, birthYear: 2001, sexRaw: "male",
            sessionsPerWeek: 4, sessionLengthMinutes: 60,
            availableEquipmentRaws: ["barbell", "dumbbell", "cable", "machine"],
            excludedMuscleRaws: [], excludedExerciseIDs: []
        )
        context.insert(profile)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<UserProfile>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.goalRaw == "buildMuscle")
        #expect(fetched.first?.availableEquipmentRaws.contains("cable") == true)
        #expect(fetched.first?.sessionsPerWeek == 4)
    }

    @Test func roundTripsBodyCompositionFields() throws {
        let container = try ModelContainer(
            for: UserProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profile = UserProfile(
            goalRaw: "buildMuscle", experienceRaw: "intermediate",
            heightCm: 178, weightKg: 76, birthYear: 2001, sexRaw: "male",
            sessionsPerWeek: 4, sessionLengthMinutes: 60,
            availableEquipmentRaws: ["barbell"], excludedMuscleRaws: [], excludedExerciseIDs: []
        )
        profile.bodyFatPercent = 18.2
        profile.skeletalMuscleMassKg = 34.8
        profile.totalBodyWaterL = 45.1
        profile.basalMetabolicRateKcal = 1_820
        profile.phaseAngleDegrees = 6.1
        context.insert(profile)
        try context.save()

        let fetched = try #require(context.fetch(FetchDescriptor<UserProfile>()).first)
        #expect(fetched.bodyFatPercent == 18.2)
        #expect(fetched.skeletalMuscleMassKg == 34.8)
        #expect(fetched.totalBodyWaterL == 45.1)
        #expect(fetched.basalMetabolicRateKcal == 1_820)
        #expect(fetched.phaseAngleDegrees == 6.1)
    }

    @Test func diskBackedContainerSurvivesContainerReopen() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("trainsage-persistence-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let configuration = ModelConfiguration(url: url)
        do {
            let container = try ModelContainer(for: UserProfile.self, BodyweightEntryModel.self, configurations: configuration)
            let context = container.mainContext
            context.insert(UserProfile(goalRaw: "maintain", experienceRaw: "beginner", heightCm: 175, weightKg: 75,
                birthYear: 1995, sexRaw: "male", sessionsPerWeek: 3, sessionLengthMinutes: 45,
                availableEquipmentRaws: [], excludedMuscleRaws: [], excludedExerciseIDs: []))
            context.insert(BodyweightEntryModel(date: .now, kg: 75, morningKg: 74.5, nightKg: 75.5))
            try context.save()
        }
        let reopened = try ModelContainer(for: UserProfile.self, BodyweightEntryModel.self, configurations: configuration)
        #expect(try reopened.mainContext.fetch(FetchDescriptor<UserProfile>()).count == 1)
        let weights = try reopened.mainContext.fetch(FetchDescriptor<BodyweightEntryModel>())
        #expect(weights.first?.kg == 75)
        #expect(weights.first?.morningKg == 74.5)
        #expect(weights.first?.nightKg == 75.5)
    }
}
