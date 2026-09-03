import Testing
@testable import RuleEngine

struct RepRangeNormalizeTests {
    @Test func defaultsProduceEightToTen() {
        let r = RepRangeNormalize.normalize(reps: nil, repsMin: nil, stride: 1)
        #expect(r.repsMin == 8)
        #expect(r.reps == 10)
    }

    @Test func explicitRangePreserved() {
        let r = RepRangeNormalize.normalize(reps: 12, repsMin: 8, stride: 1)
        #expect(r.repsMin == 8)
        #expect(r.reps == 12)
    }

    @Test func identicalBoundsEnforcesStrideSeparation() {
        let r = RepRangeNormalize.normalize(reps: 10, repsMin: 10, stride: 1)
        #expect(r.repsMin == 10)
        #expect(r.reps == 11)
    }

    @Test func strideTwoAlignment() {
        // upper = align(15, 2) = 16, lower default = max(1, 16-2) = 14 -> align(14, 2) = 14
        let r = RepRangeNormalize.normalize(reps: 15, repsMin: nil, stride: 2)
        #expect(r.repsMin == 14)
        #expect(r.reps == 16)
    }

    @Test func invertedBoundsAdjustsUpper() {
        // reps: 5 -> align(5, 2) = 6. repsMin: 9 -> align(9, 2) = 10. lower 10 >= upper 6 -> (10, 12)
        let r = RepRangeNormalize.normalize(reps: 5, repsMin: 9, stride: 2)
        #expect(r.repsMin == 10)
        #expect(r.reps == 12)
    }
}
