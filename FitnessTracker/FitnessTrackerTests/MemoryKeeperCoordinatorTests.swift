import Testing
import SwiftData
import Foundation
import FitnessDomain
import ExerciseCatalog
import Metrics
import CoachMemory
import LLMKit
@testable import FitnessTracker

@MainActor
@Suite struct MemoryKeeperCoordinatorTests {
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

    private func catalog() -> CatalogStore { CatalogStore(exercises: [exercise("bench")]) }

    private func session(note: String?) -> CompletedSessionSnapshot {
        CompletedSessionSnapshot(
            id: UUID(), date: Date(), weekday: 2, timeOfDayMinutes: 600,
            plannedDurationMin: 60, actualDurationMin: 55, energy: .normal,
            timeAvailableMin: 60, outcome: .complete, partialReason: nil,
            coachSource: .ai, plannedSessionID: nil, entries: [], overallNote: note
        )
    }

    @Test func writesNewMemoryFromModelOutput() async throws {
        let cont = try container()
        let ctx = ModelContext(cont)
        let finalTurn = """
        {"decision":"final","final":{
          "memoryCandidates":[{"kind":"constraint","statement":"Shoulder pain on overhead press.",
            "action":"Avoid overhead pressing","exerciseID":null,"muscle":"shoulders","equipment":null,
            "freeTags":[],"relation":"new","relatedMemoryID":null}],
          "measurementCandidates":[]
        }}
        """
        let provider = StubLLMProvider(responses: [.success(finalTurn)])
        let coordinator = MemoryKeeperCoordinator(
            catalog: catalog(), context: ctx, provider: provider, activeProfile: nil
        )

        await coordinator.run(session: session(note: "Shoulder hurt on overhead press today."))

        let memories = try ctx.fetch(FetchDescriptor<CoachMemoryModel>())
        #expect(memories.count == 1)
        #expect(memories[0].statement == "Shoulder pain on overhead press.")
        #expect(memories[0].kindRaw == "constraint")
    }

    @Test func writesUnconfirmedObservationFromMeasurementCandidate() async throws {
        let cont = try container()
        let ctx = ModelContext(cont)
        let finalTurn = """
        {"decision":"final","final":{
          "memoryCandidates":[],
          "measurementCandidates":[{"kind":"bodyFatPercent","value":18.2,"unit":"%"}]
        }}
        """
        let provider = StubLLMProvider(responses: [.success(finalTurn)])
        let coordinator = MemoryKeeperCoordinator(
            catalog: catalog(), context: ctx, provider: provider, activeProfile: nil
        )

        await coordinator.run(session: session(note: "InBody scan today: 18.2% body fat."))

        let observations = try ctx.fetch(FetchDescriptor<ObservationModel>())
        #expect(observations.count == 1)
        #expect(observations[0].confirmed == false)
        #expect(observations[0].value == 18.2)
    }

    @Test func rejectsImplausibleMeasurementCandidate() async throws {
        let cont = try container()
        let ctx = ModelContext(cont)
        let finalTurn = """
        {"decision":"final","final":{
          "memoryCandidates":[],
          "measurementCandidates":[{"kind":"bodyFatPercent","value":250,"unit":"%"}]
        }}
        """
        let provider = StubLLMProvider(responses: [.success(finalTurn)])
        let coordinator = MemoryKeeperCoordinator(
            catalog: catalog(), context: ctx, provider: provider, activeProfile: nil
        )

        await coordinator.run(session: session(note: "Bad reading."))

        let observations = try ctx.fetch(FetchDescriptor<ObservationModel>())
        #expect(observations.isEmpty)
    }

    @Test func noProviderIsANoOp() async throws {
        let cont = try container()
        let ctx = ModelContext(cont)
        let coordinator = MemoryKeeperCoordinator(
            catalog: catalog(), context: ctx, provider: nil, activeProfile: nil
        )

        await coordinator.run(session: session(note: "Anything"))

        #expect(try ctx.fetch(FetchDescriptor<CoachMemoryModel>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<AICallRecord>()).isEmpty)
    }

    @Test func providerFailureIsASilentNoOp() async throws {
        let cont = try container()
        let ctx = ModelContext(cont)
        let provider = StubLLMProvider(responses: [.failure(.emptyResponse)])
        let coordinator = MemoryKeeperCoordinator(
            catalog: catalog(), context: ctx, provider: provider, activeProfile: nil
        )

        await coordinator.run(session: session(note: "Anything"))

        #expect(try ctx.fetch(FetchDescriptor<CoachMemoryModel>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<AICallRecord>()).isEmpty)
    }

    @Test func emptyOutputWritesNothingButStillRecordsTheCall() async throws {
        let cont = try container()
        let ctx = ModelContext(cont)
        let finalTurn = """
        {"decision":"final","final":{"memoryCandidates":[],"measurementCandidates":[]}}
        """
        let provider = StubLLMProvider(responses: [.success(finalTurn)])
        let coordinator = MemoryKeeperCoordinator(
            catalog: catalog(), context: ctx, provider: provider, activeProfile: nil
        )

        await coordinator.run(session: session(note: "Uneventful session."))

        #expect(try ctx.fetch(FetchDescriptor<CoachMemoryModel>()).isEmpty)
        let calls = try ctx.fetch(FetchDescriptor<AICallRecord>())
        #expect(calls.count == 1)
        #expect(calls[0].callType == "memoryKeeper")
    }

    @Test func reinforcesExistingMemoryUsingItsID() async throws {
        let cont = try container()
        let ctx = ModelContext(cont)

        let existingModel = CoachMemoryModel(
            kindRaw: "preference", statement: "Prefers dumbbells over barbells", confidence: 0.3,
            sourceKind: "agent", createdAt: .now, lastConfirmedAt: .now
        )
        ctx.insert(existingModel)
        try ctx.save()

        let finalTurn = """
        {"decision":"final","final":{
          "memoryCandidates":[{"kind":"preference","statement":"Prefers dumbbells over barbells",
            "action":null,"exerciseID":null,"muscle":null,"equipment":null,
            "freeTags":[],"relation":"reinforces","relatedMemoryID":"\(existingModel.id.uuidString)"}],
          "measurementCandidates":[]
        }}
        """
        let provider = StubLLMProvider(responses: [.success(finalTurn)])
        let coordinator = MemoryKeeperCoordinator(
            catalog: catalog(), context: ctx, provider: provider, activeProfile: nil
        )

        await coordinator.run(session: session(note: "Chose dumbbells again over barbells today."))

        let memories = try ctx.fetch(FetchDescriptor<CoachMemoryModel>())
        #expect(memories.count == 1)
        #expect(memories[0].id == existingModel.id)
        #expect(abs(memories[0].confidence - 0.45) < 0.0001)
        #expect(provider.lastUser.contains(existingModel.id.uuidString))
    }
}
