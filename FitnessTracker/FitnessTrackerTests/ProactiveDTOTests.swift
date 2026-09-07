import Testing
import Foundation
@testable import FitnessTracker

@Suite struct ProactiveDTOTests {
    @Test func decodesDailyNarration() throws {
        let dto = try JSONDecoder().decode(DailyNarrationDTO.self,
            from: Data(#"{"narration":"Push day — lead with dips."}"#.utf8))
        #expect(dto.narration.contains("dips"))
    }
    @Test func decodesWeeklySummary() throws {
        let dto = try JSONDecoder().decode(WeeklySummaryDTO.self,
            from: Data(#"{"headline":"Strong week","body":"4/4 sessions.","nextWeekFocus":"More rows."}"#.utf8))
        #expect(dto.headline == "Strong week")
        #expect(dto.nextWeekFocus == "More rows.")
    }
    @Test func decodesCheckinReaction() throws {
        let dto = try JSONDecoder().decode(CheckinReactionDTO.self,
            from: Data(#"{"message":"Take it easy on legs today."}"#.utf8))
        #expect(!dto.message.isEmpty)
    }
    @Test func decodesPatternNudge() throws {
        let dto = try JSONDecoder().decode(PatternNudgeDTO.self,
            from: Data(#"{"nudge":"You've skipped pull day three weeks running."}"#.utf8))
        #expect(!dto.nudge.isEmpty)
    }
}
