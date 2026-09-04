import Testing
import FitnessDomain
import ExerciseCatalog
@testable import Metrics

@Suite struct MuscleBalanceModelTests {

    private func makeExercise(
        primary: MuscleGroup,
        secondary: [MuscleGroup] = []
    ) -> Exercise {
        Exercise(
            id: "test-\(primary.rawValue)",
            name: "Test Exercise",
            primaryMuscle: primary,
            secondaryMuscles: secondary,
            equipment: .barbell,
            mechanic: .compound,
            force: .push,
            difficulty: .intermediate,
            isUnilateral: false,
            instructions: [],
            imagePaths: []
        )
    }

    @Test func canonicalSlugCoversEveryMuscleGroup() {
        for muscle in MuscleGroup.allCases {
            #expect(!MuscleBalanceModel.canonicalSlug(for: muscle).isEmpty)
        }
    }

    @Test func displayNameFallsBackToCapitalizedForUnknownSlug() {
        #expect(MuscleBalanceModel.displayName(for: "chest") == "Chest")
        #expect(MuscleBalanceModel.displayName(for: "made-up-slug") == "Made-Up-Slug")
    }

    @Test func loadOfCreditsPrimaryInFull() {
        let ex = makeExercise(primary: .chest)
        let load = MuscleBalanceModel.loadOf(items: [.init(exercise: ex, sets: 3)])
        #expect(load["chest"] == 3.0)
    }

    @Test func loadOfCreditsSecondaryAtHalf() {
        let ex = makeExercise(primary: .chest, secondary: [.triceps, .shoulders])
        let load = MuscleBalanceModel.loadOf(items: [.init(exercise: ex, sets: 4)])
        #expect(load["chest"] == 4.0)
        #expect(load["triceps"] == 2.0)
        #expect(load["deltoids"] == 2.0)
    }

    @Test func loadOfAccumulatesAcrossItems() {
        let bench = makeExercise(primary: .chest, secondary: [.triceps])
        let fly = makeExercise(primary: .chest)
        let load = MuscleBalanceModel.loadOf(items: [
            .init(exercise: bench, sets: 3),
            .init(exercise: fly, sets: 2)
        ])
        #expect(load["chest"] == 5.0)
        #expect(load["triceps"] == 1.5)
    }

    @Test func loadOfIgnoresZeroSetItems() {
        let ex = makeExercise(primary: .biceps)
        let load = MuscleBalanceModel.loadOf(items: [.init(exercise: ex, sets: 0)])
        #expect(load.isEmpty)
    }

    @Test func rankOfSortsWorkedDescendingAndFillsMissed() {
        let load: [String: Double] = ["chest": 5.0, "biceps": 2.0]
        let (worked, missed) = MuscleBalanceModel.rankOf(load: load)
        #expect(worked == ["chest", "biceps"])
        #expect(!missed.contains("chest"))
        #expect(!missed.contains("biceps"))
        #expect(missed.contains("hamstring"))
    }

    @Test func rankOfTreatsZeroLoadAsMissed() {
        let load: [String: Double] = ["chest": 0.0]
        let (worked, missed) = MuscleBalanceModel.rankOf(load: load)
        #expect(!worked.contains("chest"))
        #expect(missed.contains("chest"))
    }

    @Test func levelsOfBucketsRelativeToBusiestMuscle() {
        // Ratios (of the busiest muscle, chest=10): biceps .65, triceps .35, abs .10 — each
        // picked to sit clear of the >= 0.75/0.50/0.25 bucket boundaries.
        let load: [String: Double] = ["chest": 10.0, "biceps": 6.5, "triceps": 3.5, "abs": 1.0]
        let levels = MuscleBalanceModel.levelsOf(load: load)
        #expect(levels["chest"] == 4)
        #expect(levels["biceps"] == 3)
        #expect(levels["triceps"] == 2)
        #expect(levels["abs"] == 1)
    }

    @Test func levelsOfEmptyLoadProducesNoEntries() {
        #expect(MuscleBalanceModel.levelsOf(load: [:]).isEmpty)
    }
}
