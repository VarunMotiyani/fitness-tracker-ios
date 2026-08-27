import Testing
@testable import FitnessDomain

@Test func muscleGroupRoundTripsThroughRawValue() throws {
    for muscle in MuscleGroup.allCases {
        #expect(MuscleGroup(rawValue: muscle.rawValue) == muscle)
    }
}

@Test func equipmentHasStableRawValues() {
    #expect(Equipment.bodyweight.rawValue == "bodyweight")
    #expect(Equipment.ezBar.rawValue == "ezBar")
}

@Test func forceTypeStaticRawValue() {
    #expect(ForceType.static.rawValue == "static")
}
