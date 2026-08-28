import Foundation
import FitnessDomain
import ExerciseCatalog
import RuleEngine
import PlanValidation
import LLMKit

nonisolated struct CallOutcome: Sendable, Equatable {
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int
    let succeeded: Bool
}

nonisolated struct CoordinatorResult: Sendable {
    let plan: WeeklyPlan
    let source: PlanSource
    let issues: [ValidationIssue]
    let call: CallOutcome?
}

nonisolated struct PlanCoordinator {
    let provider: (any LLMProvider)?
    let catalog: CatalogStore
    private let prompts: PlanPromptBuilder
    private let ruleBuilder: RulePlanBuilder
    private let validator: PlanValidator

    init(provider: (any LLMProvider)?, catalog: CatalogStore) {
        self.provider = provider
        self.catalog = catalog
        self.prompts = PlanPromptBuilder(catalog: catalog)
        self.ruleBuilder = RulePlanBuilder(catalog: catalog)
        self.validator = PlanValidator(catalog: catalog)
    }

    func makePlan(context: UserContext, weekStartDate: Date) async -> CoordinatorResult {
        guard let provider else {
            return ruleResult(context: context, weekStartDate: weekStartDate,
                              source: .ruleEngine, call: nil)
        }

        do {
            let result = try await provider.complete(
                system: prompts.system(),
                user: prompts.user(context: context),
                schema: WeeklyPlanDTO.planJSONSchema,
                as: WeeklyPlanDTO.self)
            let plan = result.value.toDomain(weekStartDate: weekStartDate, source: .ai)
            let issues = validator.validate(plan, context: context)
            let call = CallOutcome(inputTokens: result.inputTokens,
                                   outputTokens: result.outputTokens,
                                   cachedTokens: result.cachedTokens,
                                   succeeded: issues.isEmpty)
            if issues.isEmpty {
                return CoordinatorResult(plan: plan, source: .ai, issues: [], call: call)
            }
            // one retry with the validation errors fed back
            let retryUser = prompts.user(context: context, priorIssues: describe(issues))
            do {
                let retry = try await provider.complete(
                    system: prompts.system(), user: retryUser,
                    schema: WeeklyPlanDTO.planJSONSchema, as: WeeklyPlanDTO.self)
                let retryPlan = retry.value.toDomain(weekStartDate: weekStartDate, source: .ai)
                let retryIssues = validator.validate(retryPlan, context: context)
                let retryCall = CallOutcome(inputTokens: retry.inputTokens,
                                            outputTokens: retry.outputTokens,
                                            cachedTokens: retry.cachedTokens,
                                            succeeded: retryIssues.isEmpty)
                if retryIssues.isEmpty {
                    return CoordinatorResult(plan: retryPlan, source: .ai, issues: [], call: retryCall)
                }
                return ruleResult(context: context, weekStartDate: weekStartDate,
                                  source: .fallback, call: retryCall)
            } catch {
                return ruleResult(context: context, weekStartDate: weekStartDate,
                                  source: .fallback, call: call)
            }
        } catch {
            return ruleResult(context: context, weekStartDate: weekStartDate,
                              source: .fallback, call: nil)
        }
    }

    private func describe(_ issues: [ValidationIssue]) -> [String] {
        issues.map { issue in
            switch issue {
            case .unknownExerciseID(let id): "unknown exercise ID: \(id)"
            case .excludedExercisePresent(let id): "used an excluded exercise: \(id)"
            case .excludedMusclePresent(let m): "trained an excluded muscle: \(m.rawValue)"
            case .weeklyVolumeOutOfBand(let m, let sets, let band):
                "\(m.rawValue) weekly sets \(sets) outside \(band.mev)–\(band.mrv)"
            case .emptySession(let order): "session \(order + 1) has no items"
            }
        }
    }

    private func ruleResult(context: UserContext, weekStartDate: Date,
                            source: PlanSource, call: CallOutcome?) -> CoordinatorResult {
        var plan = ruleBuilder.build(context: context, weekStartDate: weekStartDate)
        if source == .fallback {
            plan = WeeklyPlan(weekStartDate: plan.weekStartDate, source: .fallback,
                              rationale: plan.rationale, sessions: plan.sessions,
                              weeklyVolumeTargets: plan.weeklyVolumeTargets)
        }
        let issues = validator.validate(plan, context: context)
        return CoordinatorResult(plan: plan, source: source, issues: issues, call: call)
    }
}
