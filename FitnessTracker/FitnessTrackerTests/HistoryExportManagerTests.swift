import Testing
import SwiftData
import Foundation
import FitnessDomain
import ExerciseCatalog
@testable import FitnessTracker

@MainActor
@Suite struct HistoryExportManagerTests {

    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: UserProfile.self, StoredPlan.self, ProviderProfile.self, AICallRecord.self,
            CompletedSessionModel.self, CompletedEntryModel.self, LoggedSetModel.self,
            BodyweightEntryModel.self, DailyCheckinModel.self, ObservationModel.self,
            PersonalRecordModel.self, CoachMemoryModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func exercise(_ id: String) -> Exercise {
        Exercise(id: id, name: "Bench Press", primaryMuscle: .chest, secondaryMuscles: [],
                 equipment: .barbell, mechanic: .compound, force: .push,
                 difficulty: .intermediate, isUnilateral: false, instructions: [], imagePaths: [])
    }

    private func catalog() -> CatalogStore {
        CatalogStore(exercises: [exercise("bench_press")])
    }

    @Test func exportCSVWithSessionsGeneratesHeadersAndRows() throws {
        let cont = try container()
        let ctx = ModelContext(cont)
        let cat = catalog()

        let session = CompletedSessionModel(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 1700000000),
            weekdayRaw: 2,
            timeOfDayMinutes: 600,
            plannedDurationMin: 60,
            energyRaw: "normal",
            timeAvailableMin: 60,
            plannedSessionID: nil
        )
        session.finishedAt = Date(timeIntervalSince1970: 1700003600)
        session.outcomeRaw = "complete"
        ctx.insert(session)

        let entry = CompletedEntryModel(
            exerciseID: "bench_press",
            performedOrder: 0
        )
        entry.session = session
        ctx.insert(entry)
        session.entries.append(entry)

        let set1 = LoggedSetModel(
            targetReps: 8,
            targetLoadKg: 80,
            actualReps: 8,
            actualLoadKg: 80,
            startedAt: Date(timeIntervalSince1970: 1700000100),
            completedAt: Date(timeIntervalSince1970: 1700000130),
            restBeforeSec: 90,
            rpe: 8.5,
            rir: 1.5,
            heldSec: nil,
            isWarmup: false
        )
        set1.entry = entry
        ctx.insert(set1)
        entry.sets.append(set1)
        try ctx.save()

        let url = HistoryExportManager.exportCSV(context: ctx, catalog: cat)
        #expect(url != nil)
        if let url {
            let csv = try String(contentsOf: url, encoding: .utf8)
            #expect(csv.contains("Date,Workout Name,Exercise Name,Set Order,Weight (kg),Reps,RIR,RPE,Rest Time (sec),Warmup,Notes"))
            #expect(csv.contains("Bench Press"))
            #expect(csv.contains("80.0,8,1.5,8.5,90,false"))
        }
    }

    @Test func exportBackupJSONGeneratesValidPayload() throws {
        let cont = try container()
        let ctx = ModelContext(cont)
        let cat = catalog()

        let bw = BodyweightEntryModel(date: Date(timeIntervalSince1970: 1700000000), kg: 75.5)
        ctx.insert(bw)
        try ctx.save()

        let url = HistoryExportManager.exportFullJSON(context: ctx, catalog: cat)
        #expect(url != nil)
        if let url {
            let data = try Data(contentsOf: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect(json != nil)
            #expect(json?["appName"] as? String == "PulseAI")
            #expect(json?["bodyweight"] != nil)
        }
    }
}
