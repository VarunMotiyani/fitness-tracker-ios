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
/// A chat exchange used to trigger a second, identical round trip through
/// this same coordinator (`run(chatExchange:)`) purely to ask "is there
/// anything worth remembering here" — a full extra system prompt + tool
/// schema on every single message just to usually answer "no". That decision
/// is now folded into `AskCoachCoordinator`'s own reply call (see
/// `AskCoachDTO.memoryCandidates`/`measurementCandidates`): the same model
/// turn that's already reading the message decides in the same structured
/// output, at the marginal cost of a couple more JSON fields instead of a
/// whole second call.
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
            .first { Calendar.appWeek.isDate($0.date, inSameDayAs: session.date) }
            .map { DailyCheckinSnapshot(date: $0.date, sleepQuality: $0.sleepQuality, soreness: $0.soreness, note: $0.note) }

        let recalled = MemoryRecall.select(
            from: existingMemories,
            context: RecallContext(exerciseIDs: Set(session.entries.map(\.exerciseID))),
            now: .now
        )

        let system = MemoryKeeperPromptBuilder.system()
        let scheduleContext = scheduleContext(for: session.date)
        let user = MemoryKeeperPromptBuilder.user(session: session, checkin: checkin,
                                                  memoryDigest: memoryDigestWithIDs(from: recalled.selected),
                                                  scheduleContext: scheduleContext)
        await runToolLoopAndApply(system: system, user: user, existingMemories: existingMemories, sessionID: session.id)
    }

    private func scheduleContext(for date: Date) -> String? {
        guard let stored = (try? context.fetch(FetchDescriptor<StoredPlan>(sortBy: [SortDescriptor(\.generatedAt, order: .reverse)])))?.first,
              (try? stored.decodedPlan()) != nil else { return nil }
        let state = WorkoutScheduleStore.isRescheduled(for: date) ? "rescheduled catch-up" : (WorkoutScheduleStore.effectiveRoutineID(for: date) == nil ? "rest" : "scheduled")
        return "Schedule context for \(WorkoutScheduleStore.calendar.startOfDay(for: date)): \(state). Use this only to understand whether the completed session filled a moved slot."
    }

    private func runToolLoopAndApply(system: String, user: String, existingMemories: [CoachMemory], sessionID: UUID?) async {
        guard let provider else { return }

        let tools = ToolRegistry(tools: [QueryTrainingDataTool(context: context, catalog: catalog)])

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
        } catch ToolLoopError.providerFailed(let partialCalls), ToolLoopError.providerFailedWithMessage(let partialCalls, _) {
            // Provider threw mid-loop — bill the sub-calls that already ran.
            recordCalls(partialCalls)
            return
        } catch {
            return // provider/decode failure — silent no-op, nothing to bill.
        }

        recordCalls(calls)
        MemoryCandidateApplication.applyMemoryCandidates(dto.memoryCandidates, existing: existingMemories, context: context)
        MemoryCandidateApplication.applyMeasurementCandidates(dto.measurementCandidates, sessionID: sessionID, context: context)
        _ = PersistenceReporter.attemptSave(context, operation: "persist context")
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
                                      success: call.succeeded, usedFallback: call.usedFallback)
            context.insert(record)
        }
        _ = PersistenceReporter.attemptSave(context, operation: "persist context")
    }
}

@MainActor
protocol MemoryKeeperRunning {
    func run(session: CompletedSessionSnapshot) async
}

/// Renders memories as "- [{uuid}] {statement} → {action}" lines so any
/// caller that echoes an ID back as `relatedMemoryID` gets one to echo —
/// shared between `MemoryKeeperCoordinator` and `AskCoachCoordinator` so a
/// single chat turn's reply and memory-extraction calls see the athlete's
/// memory the same way (design spec §3).
func memoryDigestWithIDs(from selected: [CoachMemory]) -> String {
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
