import Testing
import SwiftData
@testable import FitnessTracker

@MainActor
struct UserProfilePersistenceTests {

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
}
