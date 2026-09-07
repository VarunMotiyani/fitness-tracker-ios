import Foundation

nonisolated struct AskCoachDTO: Codable, Sendable {
    let reply: String

    private enum CodingKeys: String, CodingKey { case reply, message }

    init(reply: String) {
        self.reply = reply
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(String.self, forKey: .reply) {
            reply = value
        } else {
            reply = try container.decode(String.self, forKey: .message)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reply, forKey: .reply)
    }
}
