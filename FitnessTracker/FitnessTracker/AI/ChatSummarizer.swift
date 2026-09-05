import Foundation
import SwiftData
import LLMKit

/// Keeps `ChatMessageModel` bounded (design spec §2): once the count exceeds
/// 30, folds everything but the most recent 10 into the rolling
/// `ChatSummaryModel` and deletes the folded rows. A no-op below the
/// threshold, and a no-op (no fold, nothing billed) with no provider or on
/// any call failure — same "always safe to skip" contract as memory-keeper.
///
/// Routed through `ToolLoopRunner` with an empty tool registry rather than a
/// bare `provider.complete`: summarization genuinely needs no tools, but the
/// wire format every provider is prompted for is still the shared
/// `ToolLoopTurn` `{"decision": ..., "final": ...}` envelope (see
/// `ToolLoopSchema`/`ToolLoopRunner`), so decoding must go through the same
/// envelope rather than a bare `ChatSummaryDTO`. With zero tools the model
/// has nothing to call, so the loop always resolves on its first turn.
@MainActor
struct ChatSummarizer {
    let context: ModelContext
    let provider: (any LLMProvider)?
    let activeProfile: ProviderProfile?

    private static let threshold = 30
    private static let keepRecent = 10

    func summarizeIfNeeded() async {
        guard let provider else { return }
        let all = ((try? context.fetch(FetchDescriptor<ChatMessageModel>(sortBy: [SortDescriptor(\.timestamp)]))) ?? [])
        guard all.count > Self.threshold else { return }

        let toFold = Array(all.dropLast(Self.keepRecent))
        guard !toFold.isEmpty else { return }

        let existing = (try? context.fetch(FetchDescriptor<ChatSummaryModel>()))?.first
        let existingSummary = existing ?? ChatSummaryModel()
        let system = ChatSummaryPromptBuilder.system()
        let user = ChatSummaryPromptBuilder.user(
            existingSummary: existingSummary.text,
            messages: toFold.map { ($0.role, $0.text) }
        )

        let loopResult: ToolLoopResult<ChatSummaryDTO>
        do {
            loopResult = try await ToolLoopRunner().run(
                system: system, initialUser: user,
                finalSchema: ChatSummaryPromptBuilder.finalSchema,
                tools: ToolRegistry(tools: []), provider: provider
            )
        } catch ToolLoopError.exceededMaxIterations {
            return // never converged on a final answer — nothing to fold, nothing to bill.
        } catch {
            return // provider/decode failure — silent no-op, the transcript just stays a bit longer.
        }

        existingSummary.text = loopResult.value.summary
        existingSummary.updatedAt = .now
        existingSummary.messagesCoveredThrough = toFold.last?.timestamp
        if existing == nil { context.insert(existingSummary) }
        for message in toFold { context.delete(message) }

        for call in loopResult.calls {
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
            context.insert(AICallRecord(callType: "chatSummarize",
                                        providerDisplayName: activeProfile?.displayName ?? "—",
                                        modelID: activeProfile?.modelID ?? "—",
                                        inputTokens: call.inputTokens, outputTokens: call.outputTokens,
                                        cachedTokens: call.cachedTokens, costUSD: costUSD,
                                        success: call.succeeded, usedFallback: false))
        }
        try? context.save()
    }
}
