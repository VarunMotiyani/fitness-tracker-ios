import Foundation
import SwiftData
import CoachMemory

/// Shared write path for `memoryCandidates`/`measurementCandidates` — the same
/// two arrays `MemoryKeeperCoordinator` (session finalize) and
/// `AskCoachCoordinator` (chat, folded into its own reply call rather than a
/// second round trip) both produce. One place applies them so there is only
/// one `reconcile`/`MeasurementGuardrail` call path to trust.
@MainActor
enum MemoryCandidateApplication {
    /// Returns whether anything actually changed — callers use this to decide
    /// whether it's worth reacting (e.g. an immediate pattern-nudge check)
    /// rather than firing on every call regardless of whether the model
    /// proposed nothing or proposed a duplicate that `reconcile` dropped.
    @discardableResult
    static func applyMemoryCandidates(_ dtos: [MemoryCandidateDTO], existing: [CoachMemory], context: ModelContext) -> Bool {
        let candidates = dtos.compactMap { $0.toDomain() }
        guard !candidates.isEmpty else { return false }

        let result = MemoryConsolidation.reconcile(existing: existing, candidates: candidates, now: .now)
        guard !result.writes.isEmpty || !result.updated.isEmpty || !result.retired.isEmpty else { return false }

        for memory in result.writes {
            context.insert(coachMemoryModel(from: memory))
        }
        let existingModels = (try? context.fetch(FetchDescriptor<CoachMemoryModel>())) ?? []
        for memory in result.updated + result.retired {
            guard let model = existingModels.first(where: { $0.id == memory.id }) else { continue }
            model.confidence = memory.confidence
            model.lastConfirmedAt = memory.lastConfirmedAt
            model.action = memory.action
            model.supersededBy = memory.supersededBy
            model.retiredByCap = memory.retiredByCap
        }
        return true
    }

    static func applyMeasurementCandidates(_ dtos: [MeasurementCandidateDTO], sessionID: UUID?, context: ModelContext) {
        for dto in dtos where MeasurementGuardrail.isPlausible(kind: dto.kind, value: dto.value, unit: dto.unit) {
            let model = ObservationModel(kind: dto.kind, value: dto.value, unit: dto.unit, timestamp: .now)
            model.confirmed = false
            model.sessionID = sessionID
            context.insert(model)
        }
    }
}
