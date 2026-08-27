import Testing
@testable import FitnessDomain

@Test func userContextStoresAllInputs() {
    let ctx = UserContext(
        goal: .buildMuscle,
        experience: .intermediate,
        sessionsPerWeek: 4,
        sessionLengthMinutes: 60,
        availableEquipment: [.barbell, .dumbbell, .cable],
        excludedExerciseIDs: ["Barbell_Deadlift"],
        excludedMuscles: [.lowerBack]
    )
    #expect(ctx.sessionsPerWeek == 4)
    #expect(ctx.availableEquipment.contains(.cable))
    #expect(ctx.excludedMuscles.contains(.lowerBack))
}
