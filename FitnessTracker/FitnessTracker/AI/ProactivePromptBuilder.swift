import Foundation
import LLMKit

nonisolated enum ProactivePromptBuilder {
    static let dailyNarrationSchema = JSONSchema(json: #"{"narration": "string — one or two sentences"}"#)
    static let weeklySummarySchema = JSONSchema(json: #"{"headline": "string — short", "body": "string — 2-4 sentences", "nextWeekFocus": "string — one sentence"}"#)
    static let checkinReactionSchema = JSONSchema(json: #"{"message": "string — one or two sentences"}"#)
    static let patternNudgeSchema = JSONSchema(json: #"{"nudge": "string — one or two sentences"}"#)
    static let missedWeekTauntSchema = JSONSchema(json: #"{"taunt": "string — two or three blunt sentences"}"#)

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
            "Last week: \(sessionsCompleted) sessions completed against a plan of \(plannedPerWeek), with a \(streakWeeks)-week streak and \(prCount) new PRs.",
            muscleCoverageDigest.isEmpty ? "" : "Muscle coverage:\n\(muscleCoverageDigest)",
            memoryDigest.isEmpty ? "" : "What you know about this athlete:\n\(memoryDigest)",
            "Write the week's recap: a short headline, a 2-4 sentence body, and one sentence on what to prioritize next week. Do not describe this as X of Y when completed exceeds the plan; report the completed count and planned target separately."
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

    static func userMissedWeekTaunt(missedCount: Int, completedThisWeek: Int, plannedPerWeek: Int,
                                    skippedMusclesDigest: String, memoryDigest: String) -> String {
        [
            "The athlete's plan is \(plannedPerWeek) sessions this week. They've done \(completedThisWeek), and \(missedCount) missed session\(missedCount == 1 ? "" : "s") can no longer be fit in before the week ends.",
            skippedMusclesDigest.isEmpty ? "" : "Muscle groups they left untrained this week: \(skippedMusclesDigest).",
            memoryDigest.isEmpty ? "" : "What you know about this athlete:\n\(memoryDigest)",
            "Call it out — two or three blunt sentences, the way a trainer who's annoyed but still in your corner would. Name the number and the muscles. End pointing at next week. No pep-talk fluff."
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
