import Foundation
import SwiftData
import FitnessDomain
import ExerciseCatalog
import Metrics
import CoachMemory
import LLMKit

/// The result of an Ask Coach turn: `text` is always user-facing (shown in
/// the transcript or an error banner), and `isError` lets the caller
/// distinguish a real assistant reply from a failure without fragile
/// string-matching.
struct AskCoachReply: Sendable {
    let text: String
    let isError: Bool
}

/// Ask Coach's orchestrator (design spec §3): read-only tools plus
/// memory-logging, no proposals yet. Unlike finalize/memory-keeper, a
/// failure here is never silent — the caller is looking at the screen, so
/// `send` always returns a user-facing string, even on failure.
@MainActor
struct AskCoachCoordinator {
    let catalog: CatalogStore
    let context: ModelContext
    let provider: (any LLMProvider)?
    let activeProfile: ProviderProfile?

    func send(_ text: String) async -> AskCoachReply {
        guard let provider else {
            return AskCoachReply(text: "Set up an AI provider in Settings to talk to your coach.", isError: true)
        }

        let userMessage = ChatMessageModel(role: "user", text: text)
        context.insert(userMessage)
        try? context.save()

        let existingMemories = ((try? context.fetch(FetchDescriptor<CoachMemoryModel>())) ?? []).map { $0.toDomain() }
        let recalled = MemoryRecall.select(from: existingMemories, context: RecallContext(), now: .now)

        let recentMessages = ((try? context.fetch(FetchDescriptor<ChatMessageModel>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)]))) ?? [])
            .prefix(11).reversed()
            .filter { $0.id != userMessage.id }
            .map { (role: $0.role, text: $0.text) }
        let summary = (try? context.fetch(FetchDescriptor<ChatSummaryModel>()))?.first?.text ?? ""

        let system = AskCoachPromptBuilder.system()
        let user = AskCoachPromptBuilder.user(
            recentMessages: Array(recentMessages), summary: summary,
            memoryDigest: memoryDigestWithIDs(from: recalled.selected), newMessage: text
        )

        let tools = ToolRegistry(tools: buildTools())

        let calls: [CallOutcome]
        let dto: AskCoachDTO
        do {
            let loopResult: ToolLoopResult<AskCoachDTO> = try await ToolLoopRunner().run(
                system: system, initialUser: user,
                finalSchema: AskCoachPromptBuilder.finalSchema,
                tools: tools, provider: provider
            )
            calls = loopResult.calls
            dto = loopResult.value
        } catch ToolLoopError.exceededMaxIterations(let partialCalls) {
            // Still ran real, billable calls even though it never converged.
            recordCalls(partialCalls)
            return AskCoachReply(text: "Coach couldn't respond — try again.", isError: true)
        } catch {
            return AskCoachReply(text: "Coach couldn't respond — try again.", isError: true)
        }

        recordCalls(calls)
        let assistantMessage = ChatMessageModel(role: "assistant", text: dto.reply)
        context.insert(assistantMessage)
        try? context.save()

        Task {
            await MemoryKeeperCoordinator(catalog: catalog, context: context, provider: provider, activeProfile: activeProfile)
                .run(chatExchange: text, assistantReply: dto.reply)
            await ChatSummarizer(context: context, provider: provider, activeProfile: activeProfile).summarizeIfNeeded()
        }

        return AskCoachReply(text: dto.reply, isError: false)
    }

    private func buildTools() -> [any CoachTool] {
        let sessions = ((try? context.fetch(FetchDescriptor<CompletedSessionModel>())) ?? []).map { $0.toSnapshot() }
        let recoveryStatuses = RecoveryModel.computeRecovery(from: sessions, catalog: catalog, now: .now)

        var effectiveSetItems: [MuscleBalanceModel.EffectiveSetItem] = []
        for session in (try? context.fetch(FetchDescriptor<CompletedSessionModel>())) ?? [] {
            for entry in session.entries where !entry.skipped {
                guard let ex = catalog.exercise(id: entry.exerciseID) else { continue }
                let doneSets = entry.sets.filter { !$0.isWarmup }.count
                if doneSets > 0 { effectiveSetItems.append(.init(exercise: ex, sets: doneSets)) }
            }
        }
        let load = MuscleBalanceModel.loadOf(items: effectiveSetItems)

        let exportJSON = HistoryExportManager.exportFullJSONData(context: context, catalog: catalog) ?? Data("{}".utf8)

        return [
            GetRecoveryStatusTool(statuses: recoveryStatuses),
            GetMuscleBalanceTool(load: load),
            QueryTrainingDataTool(exportJSON: exportJSON),
            ProposeExerciseSwapTool(context: context, catalog: catalog),
            ProposeSetChangeTool(context: context),
            GetUpcomingSessionsTool(context: context, catalog: catalog)
        ]
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
            let record = AICallRecord(callType: "askCoach",
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
