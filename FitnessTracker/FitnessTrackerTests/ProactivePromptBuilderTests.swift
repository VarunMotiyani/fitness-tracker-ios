import Testing
@testable import FitnessTracker

@Suite struct ProactivePromptBuilderTests {
    @Test func systemPromptEstablishesCoachVoice() {
        #expect(ProactivePromptBuilder.system().lowercased().contains("trainer")
             || ProactivePromptBuilder.system().lowercased().contains("coach"))
    }
    @Test func dailyUserPromptIncludesSessionAndRecovery() {
        let p = ProactivePromptBuilder.userDailyNarration(
            sessionLabel: "Push Day", exerciseNames: ["Bench Press", "Dips"],
            recoveryDigest: "chest: fresh", memoryDigest: "")
        #expect(p.contains("Push Day"))
        #expect(p.contains("Dips"))
        #expect(p.contains("chest: fresh"))
    }
    @Test func weeklyUserPromptIncludesTheNumbers() {
        let p = ProactivePromptBuilder.userWeeklySummary(
            sessionsCompleted: 4, plannedPerWeek: 4, streakWeeks: 3,
            muscleCoverageDigest: "back undertrained", prCount: 2, memoryDigest: "")
        #expect(p.contains("4"))
        #expect(p.contains("back undertrained"))
    }

    @Test func weeklyUserPromptSeparatesCompletedCountFromPlanTarget() {
        let p = ProactivePromptBuilder.userWeeklySummary(
            sessionsCompleted: 20, plannedPerWeek: 4, streakWeeks: 13,
            muscleCoverageDigest: "quads undertrained", prCount: 7, memoryDigest: "")
        #expect(p.contains("20 sessions completed against a plan of 4"))
        #expect(p.contains("Do not describe this as X of Y when completed exceeds the plan"))
    }
    @Test func checkinUserPromptIncludesRatings() {
        let p = ProactivePromptBuilder.userCheckinReaction(
            soreness: 8, sleepQuality: 4, note: "quads wrecked",
            recentSessionsDigest: "legs Monday", memoryDigest: "")
        #expect(p.contains("8"))
        #expect(p.contains("quads wrecked"))
    }
    @Test func patternUserPromptIncludesTheStatement() {
        let p = ProactivePromptBuilder.userPatternNudge(
            patternStatement: "Skips pull day when busy",
            recentSessionsDigest: "push, push, legs", memoryDigest: "")
        #expect(p.contains("Skips pull day when busy"))
    }
}
