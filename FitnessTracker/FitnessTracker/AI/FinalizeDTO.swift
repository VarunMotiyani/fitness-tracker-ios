import Foundation
import FitnessDomain

struct FinalizeItemDTO: Codable, Sendable {
    let exerciseID: String
    let targetSets: Int
    let targetRepsMin: Int
    let targetRepsMax: Int
    let targetLoadKg: Double?
    let restSeconds: Int
}

nonisolated struct FinalizeDTO: Codable, Sendable {
    let items: [FinalizeItemDTO]
    let perItemRationale: [String: String]

    func toDomain(originalSession: PlannedSession) -> PlannedSession {
        let items = self.items.map { dto in
            PlannedItem(
                exerciseID: dto.exerciseID,
                targetSets: dto.targetSets,
                targetReps: RepRange(min: dto.targetRepsMin, max: dto.targetRepsMax),
                targetLoadKg: dto.targetLoadKg,
                restSeconds: dto.restSeconds,
                coachNote: originalSession.items.first { $0.exerciseID == dto.exerciseID }?.coachNote ?? ""
            )
        }
        return PlannedSession(
            id: originalSession.id,
            order: originalSession.order,
            focusMuscles: originalSession.focusMuscles,
            items: items
        )
    }
}
