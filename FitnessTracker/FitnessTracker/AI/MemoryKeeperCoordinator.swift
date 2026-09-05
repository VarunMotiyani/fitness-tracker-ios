import Foundation
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics
import CoachMemory
import LLMKit

/// The call `MemoryConsolidation.reconcile` has been waiting for since it was
/// built (design spec §5.2(1), `docs/specs/2026-09-05-memory-keeper-call-design.md`).
/// Fires after a session finishes, reads the session + today's check-in + the
/// live memory set, and proposes memory candidates (routed through the
/// existing deterministic `reconcile`) and measurement candidates (routed
/// through `MeasurementGuardrail`, landing unconfirmed for you to approve).
///
/// Unlike `SessionFinalizeCoordinator`, this call has no obligation to
/// produce anything and never falls back to anything: no provider, a thrown
/// error, an exceeded tool-loop cap, or a decode failure are all silent,
/// valid no-ops. Nothing is written, and no `AICallRecord` for a call that
/// never actually ran.
@MainActor
struct MemoryKeeperCoordinator: MemoryKeeperRunning {
    let catalog: CatalogStore
    let context: ModelContext
    let provider: (any LLMProvider)?
    let activeProfile: ProviderProfile?

    func run(session: CompletedSessionSnapshot) async {
        guard let provider else { return }

        let existingMemories = ((try? context.fetch(FetchDescriptor<CoachMemoryModel>())) ?? []).map { $0.toDomain() }

        let checkin = (try? context.fetch(FetchDescriptor<DailyCheckinModel>()))?
            .first { Calendar.isoUTC.isDate($0.date, inSameDayAs: session.date) }
            .map { DailyCheckinSnapshot(date: $0.date, sleepQuality: $0.sleepQuality, soreness: $0.soreness, note: $0.note) }

        let recalled = MemoryRecall.select(
            from: existingMemories,
            context: RecallContext(exerciseIDs: Set(session.entries.map(\.exerciseID))),
            now: .now
        )

        let exportJSON = HistoryExportManager.exportFullJSONData(context: context, catalog: catalog) ?? Data("{}".utf8)
        let tools = ToolRegistry(tools: [QueryTrainingDataTool(exportJSON: exportJSON)])

        let system = MemoryKeeperPromptBuilder.system()
        let user = MemoryKeeperPromptBuilder.user(session: session, checkin: checkin, memoryDigest: memoryDigest(from: recalled.selected))

        let calls: [CallOutcome]
        let dto: MemoryKeeperDTO
        do {
            let loopResult: ToolLoopResult<MemoryKeeperDTO> = try await ToolLoopRunner().run(
                system: system, initialUser: user,
                finalSchema: MemoryKeeperPromptBuilder.finalSchema,
                tools: tools, provider: provider
            )
            calls = loopResult.calls
            dto = loopResult.value
        } catch ToolLoopError.exceededMaxIterations(let partialCalls) {
            // Still ran real, billable calls even though it never converged.
            recordCalls(partialCalls)
            return
        } catch {
            return // provider/decode failure — silent no-op, nothing to bill.
        }

        recordCalls(calls)
        applyMemoryCandidates(dto.memoryCandidates, existing: existingMemories)
        applyMeasurementCandidates(dto.measurementCandidates, sessionID: session.id)
        try? context.save()
    }

    /// Renders `selected` as `"- [{uuid}] {statement} → {action}"` lines so the
    /// model can echo an ID back as `relatedMemoryID` (Critical Finding #1) —
    /// `MemoryRecall.digest` alone carries no IDs.
    private func memoryDigest(from selected: [CoachMemory]) -> String {
        selected
            .map { memory in
                var line = "- [\(memory.id.uuidString)] \(memory.statement)"
                if let action = memory.action, !action.isEmpty {
                    line += " → " + action
                }
                return line
            }
            .joined(separator: "\n")
    }

    private func applyMemoryCandidates(_ dtos: [MemoryCandidateDTO], existing: [CoachMemory]) {
        let candidates = dtos.compactMap { $0.toDomain() }
        guard !candidates.isEmpty else { return }

        let result = MemoryConsolidation.reconcile(existing: existing, candidates: candidates, now: .now)

        for memory in result.writes {
            context.insert(coachMemoryModel(from: memory))
        }
        let existingModels = (try? context.fetch(FetchDescriptor<CoachMemoryModel>())) ?? []
        for memory in result.updated + result.retired {
            guard let model = existingModels.first(where: { $0.id == memory.id }) else { continue }
            model.confidence = memory.confidence
            model.lastConfirmedAt = memory.lastConfirmedAt
            model.action = memory.action
            model.supersededBy = memory.supersededBy
            model.retiredByCap = memory.retiredByCap
        }
    }

    private func applyMeasurementCandidates(_ dtos: [MeasurementCandidateDTO], sessionID: UUID) {
        for dto in dtos where MeasurementGuardrail.isPlausible(kind: dto.kind, value: dto.value, unit: dto.unit) {
            let model = ObservationModel(kind: dto.kind, value: dto.value, unit: dto.unit, timestamp: .now)
            model.confirmed = false
            model.sessionID = sessionID
            context.insert(model)
        }
    }

    private func recordCalls(_ calls: [CallOutcome]) {
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
            let record = AICallRecord(callType: "memoryKeeper",
                                      providerDisplayName: activeProfile?.displayName ?? "—",
                                      modelID: activeProfile?.modelID ?? "—",
                                      inputTokens: call.inputTokens, outputTokens: call.outputTokens,
                                      cachedTokens: call.cachedTokens, costUSD: costUSD,
                                      success: call.succeeded, usedFallback: false)
            context.insert(record)
        }
        try? context.save()
    }
}

@MainActor
protocol MemoryKeeperRunning {
    func run(session: CompletedSessionSnapshot) async
}
