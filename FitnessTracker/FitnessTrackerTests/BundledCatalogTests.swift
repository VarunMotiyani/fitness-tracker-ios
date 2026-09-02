import Testing
import Foundation
import FitnessDomain
import ExerciseCatalog
@testable import FitnessTracker

struct BundledCatalogTests {

    @Test func loadsAllTwentyAndCoversMajorMuscles() throws {
        // The unit-test target is hosted by the app, so `Bundle.main` is the app bundle
        // where `catalog.json` is copied.
        let store = try BundledCatalog.load()
        #expect(store.all.count >= 20)

        for muscle in [MuscleGroup.chest, .back, .quads, .hamstrings, .glutes,
                       .shoulders, .biceps, .triceps, .calves, .abs] {
            let matches = store.exercises(primaryMuscle: muscle,
                                          availableEquipment: [.barbell, .dumbbell, .machine, .cable])
            #expect(!matches.isEmpty, "no catalog entry for \(muscle)")
        }
    }

    @Test func throwsWhenResourceMissing() {
        #expect(throws: BundledCatalogError.resourceMissing) {
            _ = try BundledCatalog.load(resourceName: "does_not_exist")
        }
    }
}
