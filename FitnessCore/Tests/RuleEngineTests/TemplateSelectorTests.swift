import Testing
import FitnessDomain
@testable import RuleEngine

@Test func beginnerCapsAtUpperLower() {
    #expect(TemplateSelector.select(sessionsPerWeek: 6, experience: .beginner).name
            == SplitTemplateLibrary.upperLower4.name)
    #expect(TemplateSelector.select(sessionsPerWeek: 2, experience: .beginner).name
            == SplitTemplateLibrary.fullBody3.name)
}

@Test func intermediateGetsPPLAtFivePlus() {
    #expect(TemplateSelector.select(sessionsPerWeek: 5, experience: .intermediate).name
            == SplitTemplateLibrary.pushPullLegs6.name)
    #expect(TemplateSelector.select(sessionsPerWeek: 4, experience: .advanced).name
            == SplitTemplateLibrary.upperLower4.name)
}
