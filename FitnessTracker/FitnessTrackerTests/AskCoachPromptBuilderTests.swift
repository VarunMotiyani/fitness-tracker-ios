import Testing
import Foundation
@testable import FitnessTracker

@Suite struct AskCoachPromptBuilderTests {
    /// The coach can now change things directly (apply_*/start_workout/
    /// regenerate_plan/etc.) — read-only is no longer the constraint. What's
    /// still true, and still worth the model being told explicitly, is that
    /// every one of those tools only ever reaches a session that hasn't
    /// started yet; the live session screen owns the one currently active.
    @Test func systemPromptStatesActiveSessionIsOffLimits() {
        let prompt = AskCoachPromptBuilder.system().lowercased()
        #expect(prompt.contains("hasn't started") || prompt.contains("currently in"))
        #expect(prompt.contains("scheduledweekday"))
    }

    @Test func userPromptIncludesNewMessage() {
        let prompt = AskCoachPromptBuilder.user(recentMessages: [], summary: "", memoryDigest: "", newMessage: "How's my recovery?")
        #expect(prompt.contains("How's my recovery?"))
    }

    @Test func userPromptIncludesRecentMessages() {
        let prompt = AskCoachPromptBuilder.user(
            recentMessages: [("user", "I hurt my shoulder"), ("assistant", "Noted, avoiding overhead work.")],
            summary: "", memoryDigest: "", newMessage: "What should I do instead?"
        )
        #expect(prompt.contains("I hurt my shoulder"))
        #expect(prompt.contains("avoiding overhead work"))
    }

    @Test func userPromptIncludesSummaryWhenPresent() {
        let prompt = AskCoachPromptBuilder.user(recentMessages: [], summary: "Athlete has a history of shoulder soreness.", memoryDigest: "", newMessage: "test")
        #expect(prompt.contains("shoulder soreness"))
    }

    @Test func userPromptOmitsSummarySectionWhenEmpty() {
        let prompt = AskCoachPromptBuilder.user(recentMessages: [], summary: "", memoryDigest: "", newMessage: "test")
        #expect(!prompt.contains("Earlier in this conversation"))
    }

    /// The actual gap behind "asked what to train at 11:30pm, got handed a
    /// start card like it was 9am" — the model had the scheduled day but no
    /// clock time at all. Without this it can't distinguish "today" at 7am
    /// from "today" at 11:30pm.
    @Test func userPromptIncludesCurrentDateTimeWhenGiven() {
        let prompt = AskCoachPromptBuilder.user(
            recentMessages: [], summary: "", memoryDigest: "",
            currentDateTime: "Friday, September 12, 2026 at 11:30 PM",
            newMessage: "what should I train today")
        #expect(prompt.contains("11:30 PM"))
    }

    @Test func userPromptOmitsDateTimeSectionWhenEmpty() {
        let prompt = AskCoachPromptBuilder.user(recentMessages: [], summary: "", memoryDigest: "", newMessage: "test")
        #expect(!prompt.contains("current local date and time"))
    }

    @Test func systemPromptTellsTheModelToReasonAboutLateNightTiming() {
        let prompt = AskCoachPromptBuilder.system().lowercased()
        #expect(prompt.contains("11:30pm") || prompt.contains("late"))
    }

    /// The auto-reschedule catch-up (`Scheduling.autoRescheduleMissedSessions`)
    /// decides the actual landing day itself, and the model has no tool to
    /// see its answer in advance — it should never promise a specific day
    /// like "tomorrow" for a skipped session.
    @Test func systemPromptWarnsAgainstPromisingASpecificCatchUpDay() {
        let prompt = AskCoachPromptBuilder.system().lowercased()
        #expect(prompt.contains("catch-up") && prompt.contains("tomorrow"))
    }
}
