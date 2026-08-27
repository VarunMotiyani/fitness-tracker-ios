import Foundation
import FitnessDomain
import ExerciseCatalog

public struct RulePlanBuilder: Sendable {
    private let catalog: CatalogStore

    public init(catalog: CatalogStore) {
        self.catalog = catalog
    }

    public func build(context: UserContext, weekStartDate: Date) -> WeeklyPlan {
        let template = TemplateSelector.select(sessionsPerWeek: context.sessionsPerWeek,
                                               experience: context.experience)
        let sessionCount = min(template.sessionCount, max(1, context.sessionsPerWeek))
        let activeFocuses = Array(template.sessionFocuses.prefix(sessionCount))

        // Step 4 — muscles in scope, ordered by the canonical enum order.
        let focusMuscleSet = Set(activeFocuses.flatMap { $0 })
            .subtracting(context.excludedMuscles)
        let scopedMuscles = MuscleGroup.allCases.filter { focusMuscleSet.contains($0) }

        let weeklyTargets: [MuscleVolumeTarget] = scopedMuscles.map { muscle in
            let mav = VolumeLandmarks.band(for: muscle, experience: context.experience).mav
            return MuscleVolumeTarget(muscle: muscle, targetSets: mav)
        }
        let targetByMuscle = Dictionary(uniqueKeysWithValues: weeklyTargets.map { ($0.muscle, $0.targetSets) })

        let sessionsTrainingMuscle: [MuscleGroup: Int] = scopedMuscles.reduce(into: [:]) { acc, muscle in
            acc[muscle] = activeFocuses.filter { $0.contains(muscle) }.count
        }

        let reps = Self.repRange(for: context.goal)

        var sessions: [PlannedSession] = []
        for (index, focus) in activeFocuses.enumerated() {
            let sessionMuscles = focus.filter { focusMuscleSet.contains($0) }
            var items: [PlannedItem] = []

            for muscle in sessionMuscles {
                guard let target = targetByMuscle[muscle],
                      let trainingCount = sessionsTrainingMuscle[muscle], trainingCount > 0 else { continue }

                let setsPerSession = max(2, Int((Double(target) / Double(trainingCount)).rounded()))

                var candidates = catalog.exercises(primaryMuscle: muscle,
                                                   availableEquipment: context.availableEquipment)
                candidates.removeAll { context.excludedExerciseIDs.contains($0.id) }
                guard !candidates.isEmpty else { continue }

                let exerciseCount = setsPerSession < 6 ? 1 : min(2, candidates.count)
                let setsEach = max(2, Int((Double(setsPerSession) / Double(exerciseCount)).rounded()))

                for exercise in candidates.prefix(exerciseCount) {
                    let rest = exercise.mechanic == .compound ? 150 : 75
                    let note = "Target \(reps.min)–\(reps.max) reps. Stop 1–2 reps short of failure."
                    items.append(PlannedItem(exerciseID: exercise.id,
                                             targetSets: setsEach,
                                             targetReps: reps,
                                             targetLoadKg: nil,
                                             restSeconds: rest,
                                             coachNote: note))
                }
            }

            sessions.append(PlannedSession(id: UUID(), order: index,
                                           focusMuscles: sessionMuscles, items: items))
        }

        let rationale = "\(template.name) — matches \(sessionCount) session(s)/week and \(context.experience.rawValue) experience."
        return WeeklyPlan(weekStartDate: weekStartDate, source: .ruleEngine,
                          rationale: rationale, sessions: sessions,
                          weeklyVolumeTargets: weeklyTargets)
    }

    static func repRange(for goal: Goal) -> RepRange {
        switch goal {
        case .getStronger:                 return RepRange(min: 4, max: 6)
        case .buildMuscle:                 return RepRange(min: 8, max: 12)
        case .loseFat, .generalFitness:    return RepRange(min: 10, max: 15)
        }
    }
}
