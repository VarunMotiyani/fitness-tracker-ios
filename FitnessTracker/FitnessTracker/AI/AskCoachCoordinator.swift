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
    /// Set when the coach called `start_workout` this turn. The coordinator
    /// can't navigate the UI itself — whichever screen hosts the chat resolves
    /// this against its own `WeeklyPlan` and starts the session.
    var startSessionID: UUID? = nil
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

    /// Sends a message, optionally preserving the message a user swiped to
    /// reply to. The stored transcript remains clean; the reply context is
    /// injected only into the model turn.
    func send(_ text: String, replyingTo replyContext: String? = nil) async -> AskCoachReply {
        guard let provider else {
            return AskCoachReply(text: "Set up an AI provider in Settings to talk to your coach.", isError: true)
        }

        let userMessage = ChatMessageModel(role: "user", text: text)
        context.insert(userMessage)
        _ = PersistenceReporter.attemptSave(context, operation: "persist context")

        let existingMemories = ((try? context.fetch(FetchDescriptor<CoachMemoryModel>())) ?? []).map { $0.toDomain() }
        let recalled = MemoryRecall.select(from: existingMemories, context: RecallContext(), now: .now)

        let recentMessages = ((try? context.fetch(FetchDescriptor<ChatMessageModel>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)]))) ?? [])
            .prefix(11).reversed()
            .filter { $0.id != userMessage.id }
            .map { (role: $0.role, text: $0.text) }
        let summary = (try? context.fetch(FetchDescriptor<ChatSummaryModel>()))?.first?.text ?? ""

        // Equipment goes in the prompt rather than a `get_equipment_profile`
        // tool round trip — it's a small static list and every swap proposal
        // needs it.
        let equipment = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first?
            .makeUserContext().availableEquipment.map(\.rawValue).sorted().joined(separator: ", ") ?? ""

        let system = AskCoachPromptBuilder.system()
        let modelMessage: String
        if let replyContext, !replyContext.isEmpty {
            modelMessage = "Replying to this earlier message from the coach:\n\"\(replyContext)\"\n\nNew message:\n\(text)"
        } else {
            modelMessage = text
        }

        let user = AskCoachPromptBuilder.user(
            recentMessages: Array(recentMessages), summary: summary,
            memoryDigest: memoryDigestWithIDs(from: recalled.selected),
            equipmentSummary: equipment,
            scheduleContext: WorkoutScheduleStore.scheduleDescription(),
            newMessage: modelMessage
        )

        let sink = CoachActionSink()
        let tools = ToolRegistry(tools: buildTools(sink: sink))

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
        } catch ToolLoopError.providerFailed(let partialCalls) {
            // Provider threw mid-loop — bill the sub-calls that already ran.
            recordCalls(partialCalls)
            return AskCoachReply(text: "Coach couldn't respond — try again.", isError: true)
        } catch ToolLoopError.providerFailedWithMessage(let partialCalls, let message) {
            // Keep provider diagnostics visible so configuration errors (such
            // as an unsupported model or response format) are actionable.
            recordCalls(partialCalls)
            return AskCoachReply(text: "Coach couldn't respond — \(message)", isError: true)
        } catch {
            return AskCoachReply(text: "Coach couldn't respond — try again.", isError: true)
        }

        recordCalls(calls)
        let assistantMessage = ChatMessageModel(role: "assistant", text: dto.reply)
        context.insert(assistantMessage)
        _ = PersistenceReporter.attemptSave(context, operation: "persist context")

        Task {
            await MemoryKeeperCoordinator(catalog: catalog, context: context, provider: provider, activeProfile: activeProfile)
                .run(chatExchange: text, assistantReply: dto.reply)
            await ChatSummarizer(context: context, provider: provider, activeProfile: activeProfile).summarizeIfNeeded()
        }

        // `regenerate_plan` only records the request (a tool can't await);
        // the actual generation needs the network and happens here, where
        // `send()` is already in an async context — same `generateAndStore`
        // path Settings/onboarding use, so it's billed and stored identically.
        var replyText = dto.reply
        if sink.requestedPlanRegeneration, let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first {
            let outcome = await generateAndStore(context: profile.makeUserContext(), activeProfile: activeProfile,
                                                 catalog: catalog, modelContext: context)
            replyText += "\n\n" + outcome.note
        }

        return AskCoachReply(text: replyText, isError: false, startSessionID: sink.startSessionID)
    }

    private func buildTools(sink: CoachActionSink) -> [any CoachTool] {
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

        return [
            GetRecoveryStatusTool(statuses: recoveryStatuses),
            GetMuscleBalanceTool(load: load),
            QueryTrainingDataTool(context: context, catalog: catalog),
            ProposeExerciseSwapTool(context: context, catalog: catalog),
            ProposeSetChangeTool(context: context),
            GetUpcomingSessionsTool(context: context, catalog: catalog),
            ProposeRoutineRevisionTool(context: context),
            StartWorkoutTool(context: context, sink: sink),
            RegeneratePlanTool(sink: sink),
            SetDayToRestTool(),
            ApplyExerciseSwapTool(context: context, catalog: catalog),
            ApplySetChangeTool(context: context),
            LogBodyweightTool(context: context)
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
                                      success: call.succeeded, usedFallback: call.usedFallback)
            context.insert(record)
        }
        _ = PersistenceReporter.attemptSave(context, operation: "persist context")
    }
}
