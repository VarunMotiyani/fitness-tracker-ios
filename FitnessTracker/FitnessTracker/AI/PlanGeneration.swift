import Foundation
import SwiftData
import FitnessDomain
import ExerciseCatalog
import LLMKit
import CoachMemory

/// Outcome of a plan-generation attempt. Carries a user-facing `note` so the UI
/// can tell "AI succeeded" / "validated then fell back" / "provider misconfigured"
/// / "no provider" apart instead of showing one generic banner for all of them.
nonisolated enum GenerationOutcome: Sendable {
    case aiSucceeded(costUSD: Double)
    case validatedFellBack(costUSD: Double)
    case aiUnavailable
    case providerError(String)
    case noProvider

    var note: String {
        switch self {
        case .aiSucceeded(let cost):
            "Coach updated · ~\(cost.formatted(.currency(code: "USD")))"
        case .validatedFellBack:
            "AI plan failed checks — used the rule-engine backup"
        case .aiUnavailable:
            "AI unavailable — used the rule-engine backup"
        case .providerError(let why):
            "AI provider not set up (\(why)) — used the backup"
        case .noProvider:
            "Coach updated (rule engine)"
        }
    }
}

/// Generates a weekly plan through the `PlanCoordinator` (AI-generate → validate →
/// retry → rule-engine fallback) and persists the result.
///
/// `@MainActor` — touches `ModelContext`, the `ProviderProfile` `@Model`, and the
/// `@MainActor` `LLMProviderFactory`. Callers convert their `UserProfile` `@Model`
/// with `makeUserContext()` first, then hand the plain value here.
@MainActor
func generateAndStore(context: UserContext,
                      activeProfile: ProviderProfile?,
                      catalog: CatalogStore,
                      modelContext: ModelContext) async -> GenerationOutcome {
    var provider: (any LLMProvider)?
    var providerErrorReason: String?
    if let activeProfile {
        do {
            provider = try LLMProviderFactory.make(from: activeProfile)
        } catch {
            provider = nil
            providerErrorReason = factoryErrorReason(error)
        }
    }

    let existingMemories = ((try? modelContext.fetch(FetchDescriptor<CoachMemoryModel>())) ?? []).map { $0.toDomain() }
    let recalled = MemoryRecall.select(from: existingMemories, context: RecallContext(), now: .now)

    let result = await PlanCoordinator(provider: provider, catalog: catalog)
        .makePlan(context: context, weekStartDate: .now, memoryDigest: recalled.digest)

    if let stored = try? StoredPlan(plan: result.plan,
                                    hadValidationIssues: !result.issues.isEmpty) {
        // Resolve every currently-pending suggestion before inserting the new plan:
        // it necessarily targeted the plan that's about to be superseded, and after
        // regeneration `SuggestionApplier` can never find that `plannedSessionID` again.
        let stalePending = (try? modelContext.fetch(FetchDescriptor<PendingCoachSuggestion>())) ?? []
        for suggestion in stalePending where suggestion.resolvedAt == nil {
            suggestion.resolvedAt = .now
            suggestion.accepted = false
        }
        modelContext.insert(stored)
        CoverageGapDetector.detect(context: modelContext, catalog: catalog, storedPlan: stored)
    }

    // One AICallRecord per paid call actually made (call-granular ledger).
    var totalCostUSD = 0.0
    for (index, call) in result.calls.enumerated() {
        let costUSD: Double
        if let activeProfile {
            costUSD = AICallRecord.cost(inputTokens: call.inputTokens,
                                        outputTokens: call.outputTokens,
                                        cachedTokens: call.cachedTokens,
                                        pricePerMTokIn: activeProfile.pricePerMTokIn,
                                        pricePerMTokOut: activeProfile.pricePerMTokOut,
                                        pricePerMTokCached: activeProfile.pricePerMTokCached)
        } else {
            costUSD = 0
        }
        totalCostUSD += costUSD
        let isLast = index == result.calls.count - 1
        let record = AICallRecord(callType: "planGeneration",
                                  providerDisplayName: activeProfile?.displayName ?? "—",
                                  modelID: activeProfile?.modelID ?? "—",
                                  inputTokens: call.inputTokens,
                                  outputTokens: call.outputTokens,
                                  cachedTokens: call.cachedTokens,
                                  costUSD: costUSD,
                                  success: call.succeeded,
                                  usedFallback: result.source == .fallback && isLast)
        modelContext.insert(record)
    }

    try? modelContext.save()

    if let providerErrorReason {
        return .providerError(providerErrorReason)
    }
    switch result.source {
    case .ai:
        return .aiSucceeded(costUSD: totalCostUSD)
    case .fallback:
        // No completed call means the provider threw before returning a plan
        // (transport error, rate limit, network down) rather than the model
        // producing a plan that failed validation.
        return result.calls.isEmpty ? .aiUnavailable : .validatedFellBack(costUSD: totalCostUSD)
    case .ruleEngine:
        return .noProvider
    }
}

private func factoryErrorReason(_ error: Error) -> String {
    switch error as? LLMProviderFactory.FactoryError {
    case .missingAPIKey: "missing API key"
    case .missingBaseURL: "missing base URL"
    case .invalidBaseURL: "invalid base URL"
    case .missingRegion: "missing region"
    case .malformedCredentials: "malformed credentials"
    case .none: "configuration error"
    }
}
