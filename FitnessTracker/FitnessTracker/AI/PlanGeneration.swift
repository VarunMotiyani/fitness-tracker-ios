import Foundation
import SwiftData
import FitnessDomain
import ExerciseCatalog

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
                      modelContext: ModelContext) async -> String {
    let provider = activeProfile.flatMap { try? LLMProviderFactory.make(from: $0) }

    let result = await PlanCoordinator(provider: provider, catalog: catalog)
        .makePlan(context: context, weekStartDate: .now)

    if let stored = try? StoredPlan(plan: result.plan,
                                    hadValidationIssues: !result.issues.isEmpty) {
        modelContext.insert(stored)
    }

    var recordedCostUSD: Double?

    if result.call != nil || provider != nil {
        let inputTokens = result.call?.inputTokens ?? 0
        let outputTokens = result.call?.outputTokens ?? 0
        let cachedTokens = result.call?.cachedTokens ?? 0
        let costUSD: Double
        if let activeProfile {
            costUSD = AICallRecord.cost(inputTokens: inputTokens,
                                        outputTokens: outputTokens,
                                        cachedTokens: cachedTokens,
                                        pricePerMTokIn: activeProfile.pricePerMTokIn,
                                        pricePerMTokOut: activeProfile.pricePerMTokOut,
                                        pricePerMTokCached: activeProfile.pricePerMTokCached)
        } else {
            costUSD = 0
        }
        recordedCostUSD = costUSD
        let record = AICallRecord(callType: "planGeneration",
                                  providerDisplayName: activeProfile?.displayName ?? "—",
                                  modelID: activeProfile?.modelID ?? "—",
                                  inputTokens: inputTokens,
                                  outputTokens: outputTokens,
                                  cachedTokens: cachedTokens,
                                  costUSD: costUSD,
                                  success: result.source == .ai,
                                  usedFallback: result.source == .fallback)
        modelContext.insert(record)
    }

    try? modelContext.save()

    switch result.source {
    case .fallback:
        return "Used the rule-engine backup"
    case .ruleEngine:
        return "Coach updated"
    case .ai:
        if let cost = recordedCostUSD {
            return "Coach updated · ~\(cost.formatted(.currency(code: "USD")))"
        }
        return "Coach updated"
    }
}
