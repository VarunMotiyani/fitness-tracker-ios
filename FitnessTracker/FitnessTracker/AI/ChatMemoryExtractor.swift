import Foundation
import SwiftData
import FitnessDomain
import CoachMemory
import LLMKit

/// Analyzes a completed chat conversation when the athlete starts a new chat,
/// extracting durable facts (preferences, constraints, goals, habits) and
/// numeric measurements into `CoachMemoryModel` and `ObservationModel`.
///
/// If the conversation is trivial (e.g. just greetings like "hi", "thanks"),
/// it exits immediately without making an AI call, saving tokens and rate limits.
@MainActor
struct ChatMemoryExtractor {
    let context: ModelContext
    let provider: (any LLMProvider)?
    let activeProfile: ProviderProfile?
    let conversationID: String

    private static var runningIDs: Set<String> = []
    private static let extractedDefaultsKey = "coach.extractedConversationIDs"

    init(
        context: ModelContext,
        provider: (any LLMProvider)?,
        activeProfile: ProviderProfile?,
        conversationID: String
    ) {
        self.context = context
        self.provider = provider
        self.activeProfile = activeProfile
        self.conversationID = conversationID
    }

    /// Evaluates whether the conversation contains non-trivial, substantive content
    /// worth evaluating by the AI for durable memories.
    static func hasSubstantiveContent(messages: [ChatMessageModel]) -> Bool {
        let userMessages = messages.filter { $0.role == "user" && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !userMessages.isEmpty else { return false }

        let trivialGreetings: Set<String> = [
            "hi", "hello", "hey", "sup", "yo", "good morning", "good evening",
            "gm", "gn", "thanks", "thank you", "thx", "ty", "bye", "goodbye",
            "cya", "ok", "okay", "k", "cool", "sure", "sounds good", "great",
            "nice", "yes", "no", "yep", "nope", "test"
        ]

        for message in userMessages {
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let stripped = text.components(separatedBy: CharacterSet.punctuationCharacters).joined()

            if trivialGreetings.contains(text) || trivialGreetings.contains(stripped) {
                continue
            }

            // Longer statements almost always contain athlete context or intent.
            if text.count >= 25 {
                return true
            }

            // Check for domain keywords in shorter statements (e.g. "knee hurts", "weighed 80kg", "prefer db")
            if containsDomainKeywords(text) {
                return true
            }
        }

        // If user sent multiple turns that weren't simple trivial greetings, analyze it.
        let nonGreetingUserCount = userMessages.filter { msg in
            let t = msg.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let s = t.components(separatedBy: CharacterSet.punctuationCharacters).joined()
            return !trivialGreetings.contains(t) && !trivialGreetings.contains(s)
        }.count

        return nonGreetingUserCount >= 2
    }

    private static func containsDomainKeywords(_ text: String) -> Bool {
        let keywords = [
            "pain", "hurt", "injury", "ache", "sore", "knee", "shoulder", "back",
            "hip", "elbow", "wrist", "ankle", "neck", "joint", "strain",
            "squat", "bench", "deadlift", "press", "curl", "row", "pull", "push",
            "lunge", "dip", "dumbbell", "barbell", "machine", "cable", "kettlebell",
            "weight", "kg", "lbs", "bodyweight", "reps", "sets", "goal", "bulk", "cut",
            "routine", "plan", "split", "day", "days", "rest", "schedule", "travel",
            "fasting", "sleep", "target", "prefer", "avoid", "swap"
        ]

        let words = Set(text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
        for kw in keywords {
            if words.contains(kw) || text.contains(kw) {
                return true
            }
        }
        return false
    }

    static func isAlreadyExtracted(conversationID: String) -> Bool {
        let set = Set(UserDefaults.standard.stringArray(forKey: extractedDefaultsKey) ?? [])
        return set.contains(conversationID)
    }

    static func markAsExtracted(conversationID: String) {
        var list = UserDefaults.standard.stringArray(forKey: extractedDefaultsKey) ?? []
        if !list.contains(conversationID) {
            list.append(conversationID)
            if list.count > 500 {
                list.removeFirst(list.count - 500)
            }
            UserDefaults.standard.set(list, forKey: extractedDefaultsKey)
        }
    }

    func extractMemoriesIfNeeded() async {
        guard let provider else { return }
        guard !conversationID.isEmpty, conversationID != "default" || hasMessagesForDefault() else { return }
        guard !Self.isAlreadyExtracted(conversationID: conversationID) else { return }
        guard !Self.runningIDs.contains(conversationID) else { return }

        Self.runningIDs.insert(conversationID)
        defer { Self.runningIDs.remove(conversationID) }

        let allMessages = ((try? context.fetch(FetchDescriptor<ChatMessageModel>(sortBy: [SortDescriptor(\.timestamp)]))) ?? [])
            .filter { $0.conversationID == conversationID && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard Self.hasSubstantiveContent(messages: allMessages) else {
            // Mark as extracted so we don't re-check a trivial conversation
            Self.markAsExtracted(conversationID: conversationID)
            return
        }

        let existingMemories = ((try? context.fetch(FetchDescriptor<CoachMemoryModel>())) ?? []).map { $0.toDomain() }
        let recalled = MemoryRecall.select(from: existingMemories, context: RecallContext(), now: .now)

        let system = ChatMemoryPromptBuilder.system()
        let user = ChatMemoryPromptBuilder.user(
            messages: allMessages.map { ($0.role, $0.text) },
            memoryDigest: memoryDigestWithIDs(from: recalled.selected)
        )

        let loopResult: ToolLoopResult<MemoryKeeperDTO>
        do {
            loopResult = try await ToolLoopRunner().run(
                system: system,
                initialUser: user,
                finalSchema: ChatMemoryPromptBuilder.finalSchema,
                tools: ToolRegistry(tools: []),
                provider: provider
            )
        } catch ToolLoopError.exceededMaxIterations(let partialCalls) {
            recordCalls(partialCalls)
            _ = PersistenceReporter.attemptSave(context, operation: "persist context")
            return
        } catch ToolLoopError.providerFailed(let partialCalls), ToolLoopError.providerFailedWithMessage(let partialCalls, _) {
            recordCalls(partialCalls)
            _ = PersistenceReporter.attemptSave(context, operation: "persist context")
            return
        } catch {
            return
        }

        let dto = loopResult.value
        _ = MemoryCandidateApplication.applyMemoryCandidates(
            dto.memoryCandidates,
            existing: existingMemories,
            context: context
        )
        MemoryCandidateApplication.applyMeasurementCandidates(
            dto.measurementCandidates,
            sessionID: nil,
            context: context
        )

        Self.markAsExtracted(conversationID: conversationID)
        recordCalls(loopResult.calls)
        _ = PersistenceReporter.attemptSave(context, operation: "persist extracted chat memories")
    }

    private func hasMessagesForDefault() -> Bool {
        let count = ((try? context.fetch(FetchDescriptor<ChatMessageModel>())) ?? [])
            .filter { $0.conversationID == conversationID }
            .count
        return count > 0
    }

    private func recordCalls(_ calls: [CallOutcome]) {
        for call in calls {
            let costUSD: Double
            if let activeProfile {
                costUSD = AICallRecord.cost(
                    inputTokens: call.inputTokens,
                    outputTokens: call.outputTokens,
                    cachedTokens: call.cachedTokens,
                    pricePerMTokIn: activeProfile.pricePerMTokIn,
                    pricePerMTokOut: activeProfile.pricePerMTokOut,
                    pricePerMTokCached: activeProfile.pricePerMTokCached
                )
            } else {
                costUSD = 0
            }
            context.insert(AICallRecord(
                callType: "chatMemoryExtract",
                providerDisplayName: activeProfile?.displayName ?? "—",
                modelID: activeProfile?.modelID ?? "—",
                inputTokens: call.inputTokens,
                outputTokens: call.outputTokens,
                cachedTokens: call.cachedTokens,
                costUSD: costUSD,
                success: call.succeeded,
                usedFallback: call.usedFallback,
                durationMs: call.durationMs
            ))
        }
    }
}

