import Foundation
import LLMKit

nonisolated enum ProactivePromptBuilder {
    static let dailyNarrationSchema = JSONSchema(json: #"{"narration": "string — one or two sentences"}"#)
    static let weeklySummarySchema = JSONSchema(json: #"{"headline": "string — short", "body": "string — 2-4 sentences", "nextWeekFocus": "string — one sentence"}"#)
    static let checkinReactionSchema = JSONSchema(json: #"{"message": "string — one or two sentences"}"#)
    static let patternNudgeSchema = JSONSchema(json: #"{"nudge": "string — one or two sentences"}"#)

    static func system() -> String {
        """
        You are an experienced, direct personal trainer reaching out to your \
        athlete between sessions. Keep it short and specific — cite an actual \
        exercise, muscle, number, or day. No filler, no generic \
        encouragement. Respond only in the required JSON shape.
        """
    }

    static func userDailyNarration(sessionLabel: String, exerciseNames: [String],
                                   recoveryDigest: String, memoryDigest: String) -> String {
        [
            "Today's session: \(sessionLabel) — \(exerciseNames.joined(separator: ", "))",
            recoveryDigest.isEmpty ? "" : "Recovery right now:\n\(recoveryDigest)",
            memoryDigest.isEmpty ? "" : "What you know about this athlete:\n\(memoryDigest)",
            "Write a one-or-two-sentence heads-up for today."
        ].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    static func userWeeklySummary(sessionsCompleted: Int, plannedPerWeek: Int, streakWeeks: Int,
                                  muscleCoverageDigest: String, prCount: Int, memoryDigest: String) -> String {
        [
            "This week: \(sessionsCompleted)/\(plannedPerWeek) sessions completed, \(streakWeeks)-week streak, \(prCount) new PRs.",
            muscleCoverageDigest.isEmpty ? "" : "Muscle coverage:\n\(muscleCoverageDigest)",
            memoryDigest.isEmpty ? "" : "What you know about this athlete:\n\(memoryDigest)",
            "Write the week's recap: a short headline, a 2-4 sentence body, and one sentence on what to prioritize next week."
        ].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    static func userCheckinReaction(soreness: Int?, sleepQuality: Int?, note: String?,
                                    recentSessionsDigest: String, memoryDigest: String) -> String {
        var lines = ["The athlete just logged a check-in:"]
        if let s = soreness { lines.append("- Soreness: \(s)/10") }
        if let q = sleepQuality { lines.append("- Sleep quality: \(q)/10") }
        if let n = note, !n.isEmpty { lines.append("- Note: \(n)") }
        return [
            lines.joined(separator: "\n"),
            recentSessionsDigest.isEmpty ? "" : "Recent sessions:\n\(recentSessionsDigest)",
            memoryDigest.isEmpty ? "" : "What you know about this athlete:\n\(memoryDigest)",
            "React in one or two sentences — a concrete adjustment or reassurance, not generic advice."
        ].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    static func userPatternNudge(patternStatement: String, recentSessionsDigest: String, memoryDigest: String) -> String {
        [
            "You've noticed this pattern in the athlete: \(patternStatement)",
            recentSessionsDigest.isEmpty ? "" : "Recent sessions:\n\(recentSessionsDigest)",
            memoryDigest.isEmpty ? "" : "What else you know:\n\(memoryDigest)",
            "Nudge them about it in one or two sentences — name the pattern and one thing to do about it."
        ].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}
