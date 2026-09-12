import Foundation
import Testing
import FitnessDomain
import ExerciseCatalog
@testable import FitnessTracker

@MainActor
struct ExerciseLibraryIntentTests {
    private let pushSession = PlannedSession(
        id: UUID(),
        order: 0,
        focusMuscles: [.chest, .triceps, .shoulders],
        items: [
            PlannedItem(
                exerciseID: "bench",
                targetSets: 3,
                targetReps: RepRange(min: 6, max: 8),
                targetLoadKg: 60,
                restSeconds: 120,
                coachNote: ""
            )
        ]
    )

    @Test func candidateMustMatchTheSessionFocus() {
        let intent = ExerciseLibraryIntent(date: .now, session: pushSession, action: .add)

        #expect(intent.accepts(chestExercise))
        #expect(intent.accepts(tricepsAccessory))
        #expect(!intent.accepts(backExercise))
    }

    @Test func replacementCopyNamesTheCurrentExercise() {
        let intent = ExerciseLibraryIntent(
            date: .now,
            session: pushSession,
            action: .replace(existingExerciseID: "bench")
        )

        #expect(intent.actionTitle(existingName: "Bench Press") == "Replace Bench Press")
    }

    @Test func pushSelectionRejectsPullMovementsEvenWhenTheirMuscleIsInFocus() {
        let mixedFocusSession = PlannedSession(
            id: UUID(),
            order: 0,
            focusMuscles: [.chest, .back],
            items: []
        )
        let intent = ExerciseLibraryIntent(date: .now, session: mixedFocusSession, action: .add)

        #expect(!intent.acceptsForToday(backExercise))
        #expect(!intent.acceptsForToday(untypedBackExercise))
        #expect(intent.acceptsForToday(chestExercise))
    }

    private var chestExercise: Exercise {
        Exercise(
            id: "machine_press",
            name: "Machine Press",
            primaryMuscle: .chest,
            secondaryMuscles: [.triceps],
            equipment: .machine,
            mechanic: .compound,
            force: .push,
            difficulty: .intermediate,
            isUnilateral: false,
            instructions: [],
            imagePaths: []
        )
    }

    private var tricepsAccessory: Exercise {
        Exercise(
            id: "pressdown",
            name: "Pressdown",
            primaryMuscle: .triceps,
            secondaryMuscles: [],
            equipment: .cable,
            mechanic: .isolation,
            force: .push,
            difficulty: .intermediate,
            isUnilateral: false,
            instructions: [],
            imagePaths: []
        )
    }

    private var backExercise: Exercise {
        Exercise(
            id: "row",
            name: "Row",
            primaryMuscle: .back,
            secondaryMuscles: [.biceps],
            equipment: .cable,
            mechanic: .compound,
            force: .pull,
            difficulty: .intermediate,
            isUnilateral: false,
            instructions: [],
            imagePaths: []
        )
    }

    private var untypedBackExercise: Exercise {
        Exercise(
            id: "chin_up",
            name: "Chin Up",
            primaryMuscle: .back,
            secondaryMuscles: [.biceps],
            equipment: .bodyweight,
            mechanic: .compound,
            force: nil,
            difficulty: .intermediate,
            isUnilateral: false,
            instructions: [],
            imagePaths: []
        )
    }
}
