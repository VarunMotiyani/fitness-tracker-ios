import Testing
import Foundation
import FitnessDomain
import ExerciseCatalog
import RuleEngine
@testable import FitnessTracker

struct PlanPromptBuilderTests {
    private func builder() throws -> PlanPromptBuilder {
        PlanPromptBuilder(catalog: try BundledCatalog.load())
    }
    private func ctx(equipment: Set<Equipment> = [.barbell, .dumbbell]) -> UserContext {
        UserContext(goal: .buildMuscle, experience: .intermediate, sessionsPerWeek: 4,
                    sessionLengthMinutes: 60, availableEquipment: equipment,
                    excludedExerciseIDs: ["0025"], excludedMuscles: [.calves])
    }

    @Test func userPromptOnlyListsOwnedNonExcludedExercises() throws {
        let u = try builder().user(context: ctx())
        #expect(u.contains("0047"))             // Incline Dumbbell Press (dumbbell, owned)
        #expect(!u.contains("0025 |"))          // Barbell Bench Press (excluded id)
        #expect(!u.contains("Standing Calf"))   // calves (excluded muscle)
        #expect(!u.contains("0027 |"))          // Lat Pulldown (cable not owned)
        #expect(u.contains("60"))               // session length
    }

    @Test func priorIssuesAppended() throws {
        let u = try builder().user(context: ctx(), priorIssues: ["session 2 was empty"])
        #expect(u.localizedCaseInsensitiveContains("previous attempt"))
        #expect(u.contains("session 2 was empty"))
    }

    @Test func systemMentionsSchemaAndIDConstraint() throws {
        let s = try builder().system()
        #expect(s.localizedCaseInsensitiveContains("only") && s.localizedCaseInsensitiveContains("exercise"))
        #expect(s.localizedCaseInsensitiveContains("json"))
    }
}
