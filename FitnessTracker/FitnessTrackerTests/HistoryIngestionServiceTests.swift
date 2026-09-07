import Testing
import SwiftData
import Foundation
import FitnessDomain
import ExerciseCatalog
@testable import FitnessTracker

@MainActor
@Suite struct HistoryIngestionServiceTests {

    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: UserProfile.self, StoredPlan.self, ProviderProfile.self, AICallRecord.self,
            CompletedSessionModel.self, CompletedEntryModel.self, LoggedSetModel.self,
            BodyweightEntryModel.self, DailyCheckinModel.self, ObservationModel.self,
            PersonalRecordModel.self, CoachMemoryModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func exercise(_ id: String, name: String) -> Exercise {
        Exercise(id: id, name: name, primaryMuscle: .chest, secondaryMuscles: [],
                 equipment: .barbell, mechanic: .compound, force: .push,
                 difficulty: .intermediate, isUnilateral: false, instructions: [], imagePaths: [])
    }

    private func catalog() -> CatalogStore {
        CatalogStore(exercises: [
            exercise("bench_press", name: "Bench Press"),
            exercise("barbell_squat", name: "Barbell Squat")
        ])
    }

    @Test func ingestsImportedSessionsAndBodyweight() throws {
        let cont = try container()
        let ctx = ModelContext(cont)
        let service = HistoryIngestionService(modelContext: ctx, catalog: catalog())

        let session = ImportedWorkoutSession(
            title: "Chest Day",
            date: Date(timeIntervalSince1970: 1700000000),
            durationSeconds: 3600,
            entries: [
                ImportedExerciseEntry(
                    exerciseName: "Bench Press",
                    category: "Chest",
                    sets: [
                        ImportedSet(weightKg: 80, reps: 8, rpe: 8.5, isWarmup: false),
                        ImportedSet(weightKg: 85, reps: 6, rpe: 9.0, isWarmup: false)
                    ]
                )
            ],
            notes: "Felt strong"
        )

        let bw = ImportedBodyweight(
            date: Date(timeIntervalSince1970: 1700000000),
            weightKg: 74.2,
            source: "Apple Health"
        )

        let count = try service.ingest(sessions: [session], bodyweights: [bw])
        #expect(count.sessions == 1)
        #expect(count.bodyweights == 1)

        let fetchedSessions = try ctx.fetch(FetchDescriptor<CompletedSessionModel>())
        #expect(fetchedSessions.count == 1)
        #expect(fetchedSessions[0].entries.count == 1)
        #expect(fetchedSessions[0].entries[0].sets.count == 2)
        #expect(fetchedSessions[0].entries[0].exerciseID == "bench_press")

        let fetchedBW = try ctx.fetch(FetchDescriptor<BodyweightEntryModel>())
        #expect(fetchedBW.count == 1)
        #expect(fetchedBW[0].kg == 74.2)
    }
}
