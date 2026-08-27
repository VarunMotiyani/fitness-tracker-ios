import Testing
import FitnessDomain
@testable import RuleEngine

@Test func fullBodyHasThreeIdenticalSessions() {
    let t = SplitTemplateLibrary.fullBody3
    #expect(t.sessionCount == 3)
    #expect(t.sessionFocuses[0] == t.sessionFocuses[2])
    #expect(t.sessionFocuses[0].contains(.chest))
}

@Test func upperLowerAlternates() {
    let t = SplitTemplateLibrary.upperLower4
    #expect(t.sessionCount == 4)
    #expect(t.sessionFocuses[0].contains(.chest))
    #expect(t.sessionFocuses[1].contains(.quads))
    #expect(t.sessionFocuses[0] == t.sessionFocuses[2])
}

@Test func libraryListsAllTemplates() {
    #expect(SplitTemplateLibrary.all.count == 3)
}
