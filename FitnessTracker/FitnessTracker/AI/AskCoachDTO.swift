import Foundation

nonisolated struct AskCoachDTO: Codable, Sendable {
    let reply: String
    /// Folded in from what used to be a second `MemoryKeeperCoordinator`
    /// round trip per chat message — same shape, same downstream
    /// application (`MemoryCandidateApplication`), just decided in this call
    /// instead of a dedicated one. Absent/empty on almost every turn.
    let memoryCandidates: [MemoryCandidateDTO]
    let measurementCandidates: [MeasurementCandidateDTO]

    private enum CodingKeys: String, CodingKey { case reply, message, memoryCandidates, measurementCandidates }

    init(reply: String, memoryCandidates: [MemoryCandidateDTO] = [], measurementCandidates: [MeasurementCandidateDTO] = []) {
        self.reply = reply
        self.memoryCandidates = memoryCandidates
        self.measurementCandidates = measurementCandidates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(String.self, forKey: .reply) {
            reply = value
        } else {
            reply = try container.decode(String.self, forKey: .message)
        }
        memoryCandidates = try container.decodeIfPresent([MemoryCandidateDTO].self, forKey: .memoryCandidates) ?? []
        measurementCandidates = try container.decodeIfPresent([MeasurementCandidateDTO].self, forKey: .measurementCandidates) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reply, forKey: .reply)
        try container.encode(memoryCandidates, forKey: .memoryCandidates)
        try container.encode(measurementCandidates, forKey: .measurementCandidates)
    }
}
