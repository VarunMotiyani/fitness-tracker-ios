import Testing
import Foundation
@testable import FitnessTracker
import FitnessDomain
import ExerciseCatalog

@Suite struct FinalizePromptBuilderTests {
    @Test func systemPromptEstablishesThePersonaAndConstraints() {
        let prompt = FinalizePromptBuilder.system()
        #expect(prompt.contains("personal trainer"))
        #expect(prompt.contains("constraint"))
        #expect(prompt.count > 200)
    }

    @Test func userPromptIncludesMemoryDigestAndTimeConstraint() {
        let session = PlannedSession(id: UUID(), order: 0, focusMuscles: [.chest],
            items: [PlannedItem(exerciseID: "0025", targetSets: 3,
                targetReps: RepRange(min: 8, max: 12), targetLoadKg: 60,
                restSeconds: 90, coachNote: "")])
        let catalog = CatalogStore(exercises: [])
        let prompt = FinalizePromptBuilder.user(
            session: session, catalog: catalog,
            memoryDigest: "- prefers RIR 2 on compounds",
            energyLabel: "Great", timeAvailableMin: 45)
        #expect(prompt.contains("prefers RIR 2 on compounds"))
        #expect(prompt.contains("45"))
        #expect(prompt.contains("Great"))
    }

    @Test func userPromptHandlesNoMemoryYet() {
        let session = PlannedSession(id: UUID(), order: 0, focusMuscles: [.chest], items: [])
        let catalog = CatalogStore(exercises: [])
        let prompt = FinalizePromptBuilder.user(
            session: session, catalog: catalog,
            memoryDigest: "", energyLabel: "Normal", timeAvailableMin: 60)
        #expect(prompt.contains("No standing memory yet"))
    }

    @Test func toDomainAppliesProposedSetsAndLoad() {
        let original = PlannedSession(id: UUID(), order: 0, focusMuscles: [.chest],
            items: [PlannedItem(exerciseID: "0025", targetSets: 3,
                targetReps: RepRange(min: 8, max: 12), targetLoadKg: 60,
                restSeconds: 90, coachNote: "controlled tempo")])
        let dto = FinalizeDTO(
            items: [FinalizeItemDTO(exerciseID: "0025", targetSets: 4,
                targetRepsMin: 8, targetRepsMax: 12, targetLoadKg: 65, restSeconds: 90)],
            perItemRationale: ["0025": "You hit all reps last time — pushing the load up."])
        let session = dto.toDomain(originalSession: original)
        #expect(session.items.first?.targetSets == 4)
        #expect(session.items.first?.targetLoadKg == 65)
        #expect(session.items.first?.coachNote == "controlled tempo")
    }

    @Test func toDomainDefaultsCoachNoteWhenExerciseIsNew() {
        let original = PlannedSession(id: UUID(), order: 0, focusMuscles: [.chest], items: [])
        let dto = FinalizeDTO(
            items: [FinalizeItemDTO(exerciseID: "9999", targetSets: 3,
                targetRepsMin: 8, targetRepsMax: 12, targetLoadKg: nil, restSeconds: 90)],
            perItemRationale: [:])
        let session = dto.toDomain(originalSession: original)
        #expect(session.items.first?.coachNote == "")
    }
}
