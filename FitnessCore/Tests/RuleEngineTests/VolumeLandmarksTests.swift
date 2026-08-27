import Testing
import FitnessDomain
@testable import RuleEngine

@Test func beginnerChestBand() {
    let band = VolumeLandmarks.band(for: .chest, experience: .beginner)
    #expect(band == VolumeBand(mev: 6, mav: 12, mrv: 18))
}

@Test func advancedReusesIntermediateRow() {
    #expect(VolumeLandmarks.band(for: .back, experience: .advanced)
            == VolumeLandmarks.band(for: .back, experience: .intermediate))
}

@Test func everyMuscleHasABand() {
    for muscle in MuscleGroup.allCases {
        let band = VolumeLandmarks.band(for: muscle, experience: .intermediate)
        #expect(band.mev <= band.mav && band.mav <= band.mrv)
    }
}
