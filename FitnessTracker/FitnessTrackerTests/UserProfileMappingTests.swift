import Testing
import FitnessDomain
@testable import FitnessTracker

@MainActor
struct UserProfileMappingTests {

    private func profile(goal: String = "buildMuscle",
                         experience: String = "intermediate",
                         equipment: [String] = ["barbell", "dumbbell"],
                         excludedMuscles: [String] = [],
                         excludedIDs: [String] = []) -> UserProfile {
        UserProfile(goalRaw: goal, experienceRaw: experience, heightCm: 175, weightKg: 75,
                    birthYear: 2000, sexRaw: "male", sessionsPerWeek: 4, sessionLengthMinutes: 60,
                    availableEquipmentRaws: equipment, excludedMuscleRaws: excludedMuscles,
                    excludedExerciseIDs: excludedIDs)
    }

    @Test func mapsCleanValues() {
        let ctx = profile().makeUserContext()
        #expect(ctx.goal == .buildMuscle)
        #expect(ctx.experience == .intermediate)
        #expect(ctx.availableEquipment == [.barbell, .dumbbell])
        #expect(ctx.sessionsPerWeek == 4)
    }

    @Test func unknownEnumRawsFallBack() {
        let ctx = profile(goal: "zzz", experience: "yyy",
                          equipment: ["barbell", "spaceship"]).makeUserContext()
        #expect(ctx.goal == .generalFitness)
        #expect(ctx.experience == .beginner)
        #expect(ctx.availableEquipment == [.barbell])   // "spaceship" dropped
    }

    @Test func exclusionsCarryThrough() {
        let ctx = profile(excludedMuscles: ["lowerBack"],
                          excludedIDs: ["Romanian_Deadlift"]).makeUserContext()
        #expect(ctx.excludedMuscles == [.lowerBack])
        #expect(ctx.excludedExerciseIDs == ["Romanian_Deadlift"])
    }
}
