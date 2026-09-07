import Testing
import Foundation
@testable import FitnessTracker

@Suite struct AskCoachDTOTests {
    @Test func decodesReply() throws {
        let json = """
        {"reply": "Your recovery looks good for chest — go ahead with today's push day."}
        """
        let dto = try JSONDecoder().decode(AskCoachDTO.self, from: Data(json.utf8))
        #expect(dto.reply.contains("push day"))
    }

    @Test func decodesCommonProviderMessageAlias() throws {
        let dto = try JSONDecoder().decode(AskCoachDTO.self, from: Data(#"{"message":"Ready when you are."}"#.utf8))
        #expect(dto.reply == "Ready when you are.")
    }
}
