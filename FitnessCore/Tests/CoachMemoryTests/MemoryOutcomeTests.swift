import Foundation
import Testing
import CoachMemory
import FitnessDomain

@Suite("MemoryOutcome")
struct MemoryOutcomeTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func memory(
        outcomeScore: Double? = nil
    ) -> CoachMemory {
        CoachMemory(
            id: UUID(),
            kind: .observation,
            statement: "test",
            action: nil,
            confidence: 0.5,
            source: .agent("test"),
            createdAt: now,
            lastConfirmedAt: now,
            supersededBy: nil,
            tags: MemoryTags(),
            outcomeScore: outcomeScore
        )
    }

    @Test("nil score + improved yields 0.3")
    func nilScoreImproved() {
        let mem = memory(outcomeScore: nil)
        let result = MemoryOutcome.applyResult(to: mem, signal: .improved)
        #expect(abs((result.outcomeScore ?? 0) - 0.3) < 1e-9)
    }

    @Test("0.3 score + improved yields 0.51")
    func scoreThreeImproved() {
        let mem = memory(outcomeScore: 0.3)
        let result = MemoryOutcome.applyResult(to: mem, signal: .improved)
        #expect(abs((result.outcomeScore ?? 0) - 0.51) < 1e-9)
    }

    @Test("0.3 score + worse yields -0.09")
    func scoreThreeWorse() {
        let mem = memory(outcomeScore: 0.3)
        let result = MemoryOutcome.applyResult(to: mem, signal: .worse)
        #expect(abs((result.outcomeScore ?? 0) - (-0.09)) < 1e-9)
    }

    @Test("0.8 score + unchanged yields 0.56")
    func scoreEightUnchanged() {
        let mem = memory(outcomeScore: 0.8)
        let result = MemoryOutcome.applyResult(to: mem, signal: .unchanged)
        #expect(abs((result.outcomeScore ?? 0) - 0.56) < 1e-9)
    }

    @Test("out-of-range weight is clamped to 0...1")
    func weightIsClamped() {
        let mem = memory(outcomeScore: 0.4)
        // weight 5 clamps to 1 -> result is exactly the delta (+1 for improved).
        let over = MemoryOutcome.applyResult(to: mem, signal: .improved, weight: 5)
        #expect(abs((over.outcomeScore ?? 0) - 1.0) < 1e-9)
        // weight -1 clamps to 0 -> score is unchanged.
        let under = MemoryOutcome.applyResult(to: mem, signal: .worse, weight: -1)
        #expect(abs((under.outcomeScore ?? 0) - 0.4) < 1e-9)
    }

    @Test("repeated improved converges toward but never exceeds 1.0")
    func convergence() {
        var mem = memory(outcomeScore: nil)
        var maxScore = 0.0
        for _ in 0..<100 {
            mem = MemoryOutcome.applyResult(to: mem, signal: .improved)
            maxScore = max(maxScore, (mem.outcomeScore ?? 0))
        }
        #expect(maxScore > 0.99)
        #expect(maxScore <= 1.0)
    }
}
