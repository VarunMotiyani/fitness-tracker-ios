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
    /// One entry per paid provider call actually made (empty when no provider /
    /// no call). On a retry this holds both calls so the ledger is call-granular.
    let calls: [CallOutcome]
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
                              source: .ruleEngine, calls: [])
        }

        do {
            let result = try await provider.complete(
                system: prompts.system(),
                user: prompts.user(context: context),
                schema: WeeklyPlanDTO.planJSONSchema,
                as: WeeklyPlanDTO.self)
            let plan = result.value.toDomain(weekStartDate: weekStartDate, source: .ai)
            let complaints = describe(validator.validate(plan, context: context))
                + structuralComplaints(plan, context: context)
            let call = CallOutcome(inputTokens: result.inputTokens,
                                   outputTokens: result.outputTokens,
                                   cachedTokens: result.cachedTokens,
                                   succeeded: complaints.isEmpty)
            var calls = [call]
            if complaints.isEmpty {
                return CoordinatorResult(plan: plan, source: .ai, issues: [], calls: calls)
            }
            // one retry with the problems (validation + structural) fed back
            let retryUser = prompts.user(context: context, priorIssues: complaints)
            do {
                let retry = try await provider.complete(
                    system: prompts.system(), user: retryUser,
                    schema: WeeklyPlanDTO.planJSONSchema, as: WeeklyPlanDTO.self)
                let retryPlan = retry.value.toDomain(weekStartDate: weekStartDate, source: .ai)
                let retryComplaints = describe(validator.validate(retryPlan, context: context))
                    + structuralComplaints(retryPlan, context: context)
                let retryCall = CallOutcome(inputTokens: retry.inputTokens,
                                            outputTokens: retry.outputTokens,
                                            cachedTokens: retry.cachedTokens,
                                            succeeded: retryComplaints.isEmpty)
                calls.append(retryCall)
                if retryComplaints.isEmpty {
                    return CoordinatorResult(plan: retryPlan, source: .ai, issues: [], calls: calls)
                }
                return ruleResult(context: context, weekStartDate: weekStartDate,
                                  source: .fallback, calls: calls)
            } catch {
                return ruleResult(context: context, weekStartDate: weekStartDate,
                                  source: .fallback, calls: calls)
            }
        } catch {
            return ruleResult(context: context, weekStartDate: weekStartDate,
                              source: .fallback, calls: [])
        }
    }

    /// Coordinator-local structural checks the frozen `PlanValidator` can't make
    /// (it derives every issue by iterating `plan.sessions`, so an empty or
    /// wrong-sized `sessions` array validates clean). Folded into the same
    /// retry→fallback machinery as the validator's issues.
    private func structuralComplaints(_ plan: WeeklyPlan, context: UserContext) -> [String] {
        if plan.sessions.isEmpty {
            return ["the plan contained no sessions; produce exactly \(context.sessionsPerWeek) training sessions"]
        }
        if plan.sessions.count != context.sessionsPerWeek {
            return ["the plan had \(plan.sessions.count) sessions but the user trains "
                + "\(context.sessionsPerWeek) days per week; produce exactly \(context.sessionsPerWeek)"]
        }
        return []
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
                            source: PlanSource, calls: [CallOutcome]) -> CoordinatorResult {
        var plan = ruleBuilder.build(context: context, weekStartDate: weekStartDate)
        if source == .fallback {
            plan = WeeklyPlan(weekStartDate: plan.weekStartDate, source: .fallback,
                              rationale: plan.rationale, sessions: plan.sessions,
                              weeklyVolumeTargets: plan.weeklyVolumeTargets)
        }
        let issues = validator.validate(plan, context: context)
        return CoordinatorResult(plan: plan, source: source, issues: issues, calls: calls)
    }
}
