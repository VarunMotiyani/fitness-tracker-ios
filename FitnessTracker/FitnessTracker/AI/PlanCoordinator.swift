import Foundation
import FitnessDomain
import ExerciseCatalog
import RuleEngine
import PlanValidation
import LLMKit
import os

nonisolated struct CallOutcome: Sendable, Equatable {
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int
    let succeeded: Bool
    /// True when this call was served by the profile's fallback provider
    /// rather than the primary (`ResilientProvider` failover).
    var usedFallback: Bool = false
    /// Wall-clock time for this one call, including any `ResilientProvider`
    /// retry/backoff — the number the athlete actually waited, not just the
    /// final successful attempt's own duration.
    var durationMs: Int = 0
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
    /// A plan request is a background enhancement; it must never leave the
    /// interactive coach spinner pending for the provider's much longer
    /// transport timeout. The rule engine is always available as a safe local
    /// fallback when this deadline is reached.
    private static let providerTimeout: Duration = .seconds(20)
    private static let log = Logger(subsystem: "com.varunmotiyani.TrainSage", category: "PlanGeneration")

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

    func makePlan(context: UserContext, weekStartDate: Date, memoryDigest: String = "") async -> CoordinatorResult {
        guard let provider else {
            Self.log.info("plan generation skipped: no provider configured; using rule engine")
            return ruleResult(context: context, weekStartDate: weekStartDate,
                              source: .ruleEngine, calls: [])
        }

        do {
            let start = Date()
            let result = try await completeWithTimeout(
                provider: provider,
                system: prompts.system(),
                user: prompts.user(context: context, memoryDigest: memoryDigest),
                schema: WeeklyPlanDTO.planJSONSchema,
                as: WeeklyPlanDTO.self)
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            let plan = result.value.toDomain(weekStartDate: weekStartDate, source: .ai)
            let complaints = describe(validator.validate(plan, context: context))
                + structuralComplaints(plan, context: context)
            let call = CallOutcome(inputTokens: result.inputTokens,
                                   outputTokens: result.outputTokens,
                                   cachedTokens: result.cachedTokens,
                                   succeeded: complaints.isEmpty,
                                   durationMs: durationMs)
            var calls = [call]
            if complaints.isEmpty {
                Self.log.info("plan AI request succeeded and passed validation; calls=1")
                return CoordinatorResult(plan: plan, source: .ai, issues: [], calls: calls)
            }
            Self.log.error("plan AI response failed local validation: \(complaints.joined(separator: " | "), privacy: .public)")
            // one retry with the problems (validation + structural) fed back
            let retryUser = prompts.user(context: context, priorIssues: complaints, memoryDigest: memoryDigest)
            do {
                let retryStart = Date()
                let retry = try await completeWithTimeout(
                    provider: provider,
                    system: prompts.system(), user: retryUser,
                    schema: WeeklyPlanDTO.planJSONSchema, as: WeeklyPlanDTO.self)
                let retryDurationMs = Int(Date().timeIntervalSince(retryStart) * 1000)
                let retryPlan = retry.value.toDomain(weekStartDate: weekStartDate, source: .ai)
                let retryComplaints = describe(validator.validate(retryPlan, context: context))
                    + structuralComplaints(retryPlan, context: context)
                let retryCall = CallOutcome(inputTokens: retry.inputTokens,
                                            outputTokens: retry.outputTokens,
                                            cachedTokens: retry.cachedTokens,
                                            succeeded: retryComplaints.isEmpty,
                                            durationMs: retryDurationMs)
                calls.append(retryCall)
                if retryComplaints.isEmpty {
                    Self.log.info("plan AI retry succeeded and passed validation; calls=2")
                    return CoordinatorResult(plan: retryPlan, source: .ai, issues: [], calls: calls)
                }
                Self.log.error("plan AI retry response failed local validation: \(retryComplaints.joined(separator: " | "), privacy: .public)")
                return ruleResult(context: context, weekStartDate: weekStartDate,
                                  source: .fallback, calls: calls)
            } catch {
                Self.log.error("plan AI retry failed: \(Self.describe(error), privacy: .public)")
                return ruleResult(context: context, weekStartDate: weekStartDate,
                                  source: .fallback, calls: calls)
            }
        } catch {
            Self.log.error("plan AI request failed: \(Self.describe(error), privacy: .public)")
            return ruleResult(context: context, weekStartDate: weekStartDate,
                              source: .fallback, calls: [])
        }
    }

    /// Keep diagnostics useful while limiting them to provider error details.
    /// API keys are never part of ``LLMError``; adapter HTTP bodies are already
    /// redacted before they reach this layer.
    private static func describe(_ error: Error) -> String {
        switch error as? LLMError {
        case .visionUnsupported:
            return "vision unsupported"
        case .emptyResponse:
            return "empty response"
        case .rateLimited:
            return "rate limited"
        case .transport(let message):
            return "transport: \(message)"
        case .decoding(let message):
            return "decoding: \(message)"
        case .unsupported(let message):
            return "unsupported: \(message)"
        case .none:
            return String(describing: error)
        }
    }

    /// Races one provider request against a short, explicit deadline. URLSession
    /// remains configured with its normal transport timeout for ordinary calls;
    /// this narrower product-level deadline keeps regeneration responsive and
    /// lets `makePlan` route timeout errors through its existing local fallback.
    private func completeWithTimeout<Value: Decodable & Sendable>(
        provider: any LLMProvider,
        system: String,
        user: String,
        schema: JSONSchema,
        as type: Value.Type
    ) async throws -> LLMResult<Value> {
        try await withThrowingTaskGroup(of: LLMResult<Value>.self) { group in
            group.addTask {
                try await provider.complete(system: system, user: user, schema: schema, as: type)
            }
            group.addTask {
                try await Task.sleep(for: Self.providerTimeout)
                throw LLMError.transport("AI request timed out after 20 seconds")
            }

            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw LLMError.emptyResponse
            }
            return result
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
