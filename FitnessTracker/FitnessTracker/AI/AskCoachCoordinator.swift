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

        // Same call that wrote the reply also decided what's worth
        // remembering — no separate memory-keeper round trip for chat any
        // more (see MemoryKeeperCoordinator's doc comment).
        let memoryChanged = MemoryCandidateApplication.applyMemoryCandidates(
            dto.memoryCandidates, existing: existingMemories, context: context)
        MemoryCandidateApplication.applyMeasurementCandidates(dto.measurementCandidates, sessionID: nil, context: context)

        // Every action the model actually performed gets its own card message
        // right after the reply, instead of the reply's prose being the only
        // record of what happened — a card the athlete can see is a real
        // outcome; a sentence claiming one happened is just the model's word
        // for it.
        for request in sink.cardRequests {
            let cardMessage = ChatMessageModel(role: "assistant", text: "",
                                               cardKindRaw: request.kind.rawValue, cardPayloadJSON: request.payloadJSON)
            context.insert(cardMessage)
        }

        // `regenerate_plan` only records the request (a tool can't await); the
        // actual generation needs the network and happens here, where `send()`
        // is already in an async context — same `generateAndStore` path
        // Settings/onboarding use, so it's billed and stored identically. The
        // card is inserted `.pending` now (so the transcript shows a live
        // status immediately) and mutated in place once generation settles —
        // this used to append the outcome as plain text onto the reply, which
        // silently vanished whenever the append happened after the caller had
        // already read `AskCoachReply.text`.
        var regenerationCard: ChatMessageModel?
        if sink.requestedPlanRegeneration {
            let card = ChatMessageModel(role: "assistant", text: "", cardKindRaw: ChatCardKind.planRegeneration.rawValue)
            card.setCardPayload(PlanRegenerationCardPayload(status: .pending, detail: nil))
            context.insert(card)
            regenerationCard = card
        }
        _ = PersistenceReporter.attemptSave(context, operation: "persist context")

        Task {
            await ChatSummarizer(context: context, provider: provider, activeProfile: activeProfile).summarizeIfNeeded()
            // React right away instead of waiting for the next app
            // open/background — same check `ProactiveCoordinator.runDueChecks`
            // already runs, just triggered by the memory write itself. Still
            // a no-op for almost every write: it only ever fires for a
            // high-confidence "responsePattern" memory, and only once per
            // pattern per 14 days (runPatternNudges' own cooldown).
            if memoryChanged, ProactiveSettingsStore.current().patternOn {
                await ProactiveCoordinator(
                    context: context, catalog: catalog, provider: provider,
                    activeProfile: activeProfile, settings: ProactiveSettingsStore.current()
                ).runPatternNudges()
            }
        }

        if let regenerationCard {
            if let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first {
                // `generateAndStore` always ends in a stored plan — AI, or a
                // rule-engine fallback when AI fails/is unavailable/misconfigured
                // — there's no case where regeneration produces nothing, so this
                // card's `.failed` state is reserved for this coordinator's own
                // failure below (no profile), not for `GenerationOutcome`.
                let outcome = await generateAndStore(context: profile.makeUserContext(), activeProfile: activeProfile,
                                                     catalog: catalog, modelContext: context)
                regenerationCard.setCardPayload(PlanRegenerationCardPayload(status: .succeeded, detail: outcome.note))
            } else {
                regenerationCard.setCardPayload(PlanRegenerationCardPayload(
                    status: .failed, detail: "No athlete profile found."))
            }
            _ = PersistenceReporter.attemptSave(context, operation: "persist context")
        }

        return AskCoachReply(text: dto.reply, isError: false)
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
            ProposeExerciseSwapTool(context: context, catalog: catalog, sink: sink),
            ProposeSetChangeTool(context: context, sink: sink),
            GetUpcomingSessionsTool(context: context, catalog: catalog),
            ProposeRoutineRevisionTool(context: context),
            StartWorkoutTool(context: context, sink: sink),
            RegeneratePlanTool(sink: sink),
            SetDayToRestTool(sink: sink),
            ApplyExerciseSwapTool(context: context, catalog: catalog, sink: sink),
            ApplySetChangeTool(context: context, catalog: catalog, sink: sink),
            LogBodyweightTool(context: context, sink: sink)
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
