import Testing
import FitnessDomain
import ExerciseCatalog
import RuleEngine
@testable import FitnessTracker

@MainActor
struct SplitTemplateBrowserTests {
    @Test func splitBrowserSearchesAllBuiltInTemplates() {
        #expect(SplitTemplateBrowser.templates(matching: "arnold").map(\.name)
                == [SplitTemplateLibrary.arnold6.name])
        #expect(SplitTemplateBrowser.templates(matching: "upper")
                .contains { $0.name == SplitTemplateLibrary.upperLower4.name })
        #expect(SplitTemplateBrowser.templates(matching: "") .count
                == SplitTemplateLibrary.all.count)
    }

    @Test func emptyRoutineOffersEditingInsteadOfStartingAnEmptySession() {
        let empty = RoutineDraft(name: "New Routine", exercises: [])
        let populated = RoutineDraft(name: "Push Day", exercises: [
            ExerciseConfig(exerciseID: "bench")
        ])

        #expect(RoutineCardAction.action(for: empty) == .edit)
        #expect(RoutineCardAction.action(for: populated) == .start)
    }
}
