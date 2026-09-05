import Foundation
import FitnessDomain
import CoachMemory

struct MeasurementCandidateDTO: Codable, Sendable {
    let kind: String
    let value: Double
    let unit: String
}

struct MemoryCandidateDTO: Codable, Sendable {
    let kind: String
    let statement: String
    let action: String?
    let exerciseID: String?
    let muscle: String?
    let equipment: String?
    let freeTags: [String]
    let relation: String
    let relatedMemoryID: String?

    /// `nil` on any malformed field — an unrecognized `kind`/`relation`, or a
    /// non-`new` relation missing a parseable id. The model never crashes the
    /// coordinator; a malformed candidate is simply dropped (design spec §5:
    /// "drop the candidate ... treat as .new per reconcile's own unknown-id
    /// handling" applies only when the id itself fails to parse but relation
    /// is otherwise valid — an unparseable relation/kind drops entirely).
    nonisolated func toDomain() -> MemoryCandidate? {
        guard let memoryKind = MemoryKind(rawValue: kind) else { return nil }

        let relationValue: CandidateRelation
        switch relation {
        case "new":
            relationValue = .new
        case "reinforces":
            if let idString = relatedMemoryID, let id = UUID(uuidString: idString) {
                relationValue = .reinforces(id)
            } else {
                relationValue = .new   // unknown/missing id -> treat as new, per reconcile's own handling
            }
        case "contradicts":
            if let idString = relatedMemoryID, let id = UUID(uuidString: idString) {
                relationValue = .contradicts(id)
            } else {
                relationValue = .new
            }
        default:
            return nil
        }

        let tags = MemoryTags(
            exerciseID: exerciseID,
            muscle: muscle.flatMap(MuscleGroup.init(rawValue:)),
            equipment: equipment.flatMap(Equipment.init(rawValue:)),
            freeTags: freeTags
        )

        return MemoryCandidate(kind: memoryKind, statement: statement, action: action,
                               tags: tags, relation: relationValue)
    }
}

nonisolated struct MemoryKeeperDTO: Codable, Sendable {
    let memoryCandidates: [MemoryCandidateDTO]
    let measurementCandidates: [MeasurementCandidateDTO]
}
