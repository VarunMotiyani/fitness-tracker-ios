import Testing
import SwiftData
import Foundation
import FitnessDomain
import ExerciseCatalog
import Metrics
@testable import FitnessTracker

@MainActor
@Suite struct ExerciseSwapTests {

    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: UserProfile.self, StoredPlan.self, ProviderProfile.self, AICallRecord.self,
            CompletedSessionModel.self, CompletedEntryModel.self, LoggedSetModel.self,
            BodyweightEntryModel.self, DailyCheckinModel.self, ObservationModel.self,
            PersonalRecordModel.self, CoachMemoryModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func exercise(_ id: String) -> Exercise {
        Exercise(id: id, name: id, primaryMuscle: .chest, secondaryMuscles: [],
                 equipment: .barbell, mechanic: .compound, force: .push,
                 difficulty: .intermediate, isUnilateral: false, instructions: [], imagePaths: [])
    }

    private func catalog() -> CatalogStore {
        CatalogStore(exercises: [
            exercise("bench"),
            exercise("incline_bench"),
            exercise("dumbbell_press")
        ])
    }

    private func emptyRepo() -> InMemoryMetricsRepository {
        InMemoryMetricsRepository(sessions: [], priorPRs: [], observations: [],
                                  plannedSessionsPerWeek: 3, catalog: catalog())
    }

    private func finalizer() -> RuleEngineFinalizer {
        RuleEngineFinalizer(catalog: catalog(), repository: emptyRepo())
    }

    private func plannedSession() -> PlannedSession {
        PlannedSession(id: UUID(), order: 0, focusMuscles: [.chest], items: [
            PlannedItem(exerciseID: "bench", targetSets: 3, targetReps: RepRange(min: 6, max: 8),
                        targetLoadKg: 60, restSeconds: 90, coachNote: ""),
        ])
    }

    @Test func swapExerciseReplacesExerciseIDInActiveSession() async throws {
        let cont = try container()
        let ctx = ModelContext(cont)
        let cat = catalog()
        let runner = SessionRunner(modelContext: ctx, catalog: cat,
                                   repository: emptyRepo(), finalizer: finalizer(), now: { Date() })

        let plan = plannedSession()
        await runner.start(planned: plan, energy: .normal, timeAvailableMin: 60)
        #expect(runner.entriesInOrder.count == 1)
        #expect(runner.entriesInOrder[0].exerciseID == "bench")

        let replacement = cat.exercise(id: "dumbbell_press")!
        runner.swapExercise(at: 0, to: replacement.id)

        #expect(runner.entriesInOrder[0].exerciseID == "dumbbell_press")
    }
}
