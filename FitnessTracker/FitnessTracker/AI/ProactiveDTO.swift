import Foundation

nonisolated struct DailyNarrationDTO: Codable, Sendable { let narration: String }
nonisolated struct WeeklySummaryDTO: Codable, Sendable {
    let headline: String
    let body: String
    let nextWeekFocus: String
}
nonisolated struct CheckinReactionDTO: Codable, Sendable { let message: String }
nonisolated struct PatternNudgeDTO: Codable, Sendable { let nudge: String }
