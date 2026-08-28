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
                    excludedExerciseIDs: ["Barbell_Bench_Press"], excludedMuscles: [.calves])
    }

    @Test func userPromptOnlyListsOwnedNonExcludedExercises() throws {
        let u = try builder().user(context: ctx())
        #expect(u.contains("Dumbbell_Bench_Press"))       // dumbbell, owned
        #expect(!u.contains("Barbell_Bench_Press"))        // excluded id
        #expect(!u.contains("Standing_Calf_Raise"))        // machine (not owned) AND calves (excluded)
        #expect(!u.contains("Cable_Crossover"))            // cable not owned
        #expect(u.contains("60"))                          // session length
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
