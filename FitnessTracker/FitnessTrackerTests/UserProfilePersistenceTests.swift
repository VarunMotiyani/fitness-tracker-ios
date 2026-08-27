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
}
