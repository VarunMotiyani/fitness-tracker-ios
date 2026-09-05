import Foundation
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics
import RuleEngine
import CoachMemory
import LLMKit

/// Puts the AI coach behind the existing rule-engine finalize seam (design
/// spec §2.2, §8): one well-orchestrated tool-loop call, `FinalizeGuardrail`-
/// checked, one retry with the violation fed back, then the deterministic
/// `RuleEngineFinalizer` if the AI's output fails twice or no provider is
/// configured. Never throws to its caller — every failure path resolves to
/// the rule-engine result with `coachSource: .rule`.
///
/// Tool coverage is deliberately partial for now: `PlateMathTool`,
/// `EstimateOneRepMaxTool`, and `QueryTrainingDataTool` are wired in, since
/// they need nothing beyond `catalog`/`context`. `GetRecoveryStatusTool` and
/// `GetMuscleBalanceTool` exist and are tested (Task 4) but aren't wired in
/// here yet — they need a `[CompletedSessionSnapshot]` builder this
/// coordinator doesn't have, since `MetricsRepository` doesn't expose raw
/// session snapshots. That's a real follow-up, not an oversight.
@MainActor
struct SessionFinalizeCoordinator: SessionFinalizing {
    let catalog: CatalogStore
    let context: ModelContext
    let provider: (any LLMProvider)?
    /// Kept alongside `provider` purely for billing metadata (display name,
    /// model id, per-token pricing) — `provider` itself carries none of that,
    /// same split `PlanGeneration.generateAndStore` uses.
    let activeProfile: ProviderProfile?
    let memories: [CoachMemory]
    let ruleEngineFallback: RuleEngineFinalizer

    func finalize(_ planned: PlannedSession, energy: EnergyRating, timeAvailableMin: Int) async -> FinalizedResult {
        guard let provider else {
            return await ruleEngineFallback.finalize(planned, energy: energy, timeAvailableMin: timeAvailableMin)
        }

        let recalled = MemoryRecall.select(
            from: memories,
            context: RecallContext(
                exerciseIDs: Set(planned.items.map(\.exerciseID)),
                muscles: Set(planned.focusMuscles)
            ),
            now: .now
        )

        let exportJSON = HistoryExportManager.exportFullJSONData(context: context, catalog: catalog) ?? Data("{}".utf8)
        let tools = ToolRegistry(tools: [
            PlateMathTool(),
            EstimateOneRepMaxTool(),
            QueryTrainingDataTool(exportJSON: exportJSON),
        ])

        let system = FinalizePromptBuilder.system()
        let baseUser = FinalizePromptBuilder.user(
            session: planned, catalog: catalog, memoryDigest: recalled.digest,
            energyLabel: energyLabel(energy), timeAvailableMin: timeAvailableMin
        )

        let guardrail = FinalizeGuardrail(catalog: catalog)
        var lastViolationSummary: String?
        var allCalls: [CallOutcome] = []

        for _ in 0..<2 {
            let user = lastViolationSummary.map { "\(baseUser)\n\nYour previous attempt was rejected: \($0). Try again, staying within safe bounds." } ?? baseUser
            do {
                let loopResult: ToolLoopResult<FinalizeDTO> = try await ToolLoopRunner().run(
                    system: system, initialUser: user,
                    finalSchema: FinalizePromptBuilder.finalSchema,
                    tools: tools, provider: provider
                )
                allCalls += loopResult.calls
                let dto = loopResult.value
                let candidate = dto.toDomain(originalSession: planned)
                let report = guardrail.check(
                    finalized: candidate,
                    experience: .intermediate,
                    excludedExerciseIDs: [],
                    excludedMuscles: [],
                    availableEquipment: Set(Equipment.allCases),
                    lastPerformances: [:],
                    timeAvailableMin: timeAvailableMin
                )
                if report.violations.isEmpty {
                    recordCalls(allCalls, usedFallback: false)
                    let finalized = FinalizedSession(session: candidate, perItemRationale: dto.perItemRationale)
                    return FinalizedResult(session: finalized, coachSource: .ai)
                }
                lastViolationSummary = report.violations.map(describe).joined(separator: "; ")
            } catch ToolLoopError.exceededMaxIterations(let calls) {
                allCalls += calls
                break
            } catch {
                break // provider/tool-loop failure — fall straight through to the rule engine.
            }
        }
        recordCalls(allCalls, usedFallback: true)
        return await ruleEngineFallback.finalize(planned, energy: energy, timeAvailableMin: timeAvailableMin)
    }

    /// One `AICallRecord` per underlying provider call actually made
    /// (call-granular ledger, same pattern as `PlanGeneration.generateAndStore`).
    /// `usedFallback` is true only when every one of these calls ultimately
    /// led to the rule-engine result, not the AI's.
    private func recordCalls(_ calls: [CallOutcome], usedFallback: Bool) {
        guard !calls.isEmpty else { return }
        for call in calls {
            let costUSD: Double
            if let activeProfile {
                costUSD = AICallRecord.cost(inputTokens: call.inputTokens, outputTokens: call.outputTokens,
                                            cachedTokens: call.cachedTokens,
                                            pricePerMTokIn: activeProfile.pricePerMTokIn,
                                            pricePerMTokOut: activeProfile.pricePerMTokOut,
                                            pricePerMTokCached: activeProfile.pricePerMTokCached)
            } else {
                costUSD = 0
            }
            let record = AICallRecord(callType: "finalize",
                                      providerDisplayName: activeProfile?.displayName ?? "—",
                                      modelID: activeProfile?.modelID ?? "—",
                                      inputTokens: call.inputTokens, outputTokens: call.outputTokens,
                                      cachedTokens: call.cachedTokens, costUSD: costUSD,
                                      success: call.succeeded, usedFallback: usedFallback)
            context.insert(record)
        }
        try? context.save()
    }

    private func energyLabel(_ energy: EnergyRating) -> String {
        switch energy {
        case .beat: "Beat"
        case .normal: "Normal"
        case .great: "Great"
        }
    }

    private func describe(_ violation: GuardrailViolation) -> String {
        switch violation {
        case .loadJumpTooLarge(let id, let proposed, let capped):
            return "\(id): load jump to \(proposed) kg too large, capped at \(capped) kg"
        case .loadDropTooLarge(let id, let proposed, let capped):
            return "\(id): load drop to \(proposed) kg too large, capped at \(capped) kg"
        case .weeklyVolumeOutOfBand(let muscle, let sets, let mev, let mrv):
            return "\(muscle.rawValue): \(sets) weekly sets outside \(mev)-\(mrv)"
        case .repTargetOutOfRange(let id, let target, let allowed):
            return "\(id): rep target \(target.min)-\(target.max) outside \(allowed.min)-\(allowed.max)"
        case .excludedExercise(let id):
            return "\(id): not available (equipment/exclusion)"
        case .sessionTooLong(let estimated, let available):
            return "session estimated \(estimated) min exceeds \(available) min available"
        }
    }
}
