import SwiftUI
import FitnessDomain
import ExerciseCatalog

/// The structured-card counterpart to `CoachChatBubble` — rendered instead of
/// the plain-text bubble for any `ChatMessageModel` with a non-nil
/// `cardKindRaw`. Each case owns its own compact layout; none of them use the
/// speech-bubble chrome (swipe-to-reply, copy) that only makes sense for text.
struct ChatCardView: View {
    let message: ChatMessageModel
    let catalog: CatalogStore
    let pendingSuggestions: [PendingCoachSuggestion]
    let storedPlan: StoredPlan?
    let plan: WeeklyPlan?
    let onStartSession: ((PlannedSession) -> Void)?

    @Environment(\.modelContext) private var context

    var body: some View {
        switch message.cardKind {
        case .suggestion:
            if let payload = message.decodedCardPayload(as: SuggestionCardPayload.self) {
                suggestionCard(for: payload)
            }
        case .appliedChange:
            if let payload = message.decodedCardPayload(as: AppliedChangeCardPayload.self) {
                AppliedChangeCardRow(payload: payload)
            }
        case .planRegeneration:
            if let payload = message.decodedCardPayload(as: PlanRegenerationCardPayload.self) {
                PlanRegenerationCardRow(payload: payload)
            }
        case .startWorkout:
            if let payload = message.decodedCardPayload(as: StartWorkoutCardPayload.self) {
                StartWorkoutCardRow(payload: payload, plan: plan, onStart: onStartSession)
            }
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private func suggestionCard(for payload: SuggestionCardPayload) -> some View {
        if let suggestion = pendingSuggestions.first(where: { $0.id == payload.suggestionID }) {
            if suggestion.resolvedAt == nil {
                SuggestionCard(
                    suggestion: suggestion,
                    catalog: catalog,
                    onAccept: {
                        guard let storedPlan else { return }
                        do {
                            try SuggestionApplier.apply(suggestion, storedPlan: storedPlan, context: context)
                            _ = PersistenceReporter.attemptSave(context, operation: "persist context")
                        } catch {
                            // Same as Home's card: apply() throws before mutating
                            // `suggestion` on failure, so it just stays pending.
                        }
                    },
                    onSkip: {
                        SuggestionApplier.skip(suggestion, context: context)
                        _ = PersistenceReporter.attemptSave(context, operation: "persist context")
                    }
                )
            } else {
                ResolvedSuggestionRow(accepted: suggestion.accepted == true)
            }
        }
        // If the suggestion row is gone entirely (rare — only if something else
        // deleted it), show nothing rather than a card with a broken accept path.
    }
}

/// The suggestion was already accepted/skipped — from Home, or from this same
/// card a moment ago (`@Query` re-renders this once `resolvedAt` changes).
private struct ResolvedSuggestionRow: View {
    let accepted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: accepted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(accepted ? GymTheme.lime : GymTheme.label3)
            Text(accepted ? "Suggestion accepted" : "Suggestion skipped")
                .font(.footnote.weight(.medium))
                .foregroundStyle(GymTheme.label2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// A direct-action tool (apply_*, log_bodyweight, set_day_to_rest) that
/// already completed — confirmation only, no input needed.
struct AppliedChangeCardRow: View {
    let payload: AppliedChangeCardPayload

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(GymTheme.lime.opacity(0.16)).frame(width: 36, height: 36)
                Image(systemName: payload.icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(GymTheme.lime)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(payload.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(GymTheme.label)
                Text(payload.detail)
                    .font(.footnote)
                    .foregroundStyle(GymTheme.label2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

/// `regenerate_plan`'s lifecycle in one card: inserted `.pending`, mutated in
/// place to `.succeeded`/`.failed` once `generateAndStore` finishes —
/// SwiftData's `@Query` re-renders this exact row live, no polling needed.
struct PlanRegenerationCardRow: View {
    let payload: PlanRegenerationCardPayload

    var body: some View {
        HStack(spacing: 12) {
            switch payload.status {
            case .pending:
                ProgressView().controlSize(.small).tint(GymTheme.lime)
            case .succeeded:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(GymTheme.lime)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(GymTheme.red)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(GymTheme.label)
                if let detail = payload.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(GymTheme.label2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch payload.status {
        case .pending: "Rebuilding your plan…"
        case .succeeded: "Plan rebuilt"
        case .failed: "Couldn't rebuild your plan"
        }
    }
}

/// `start_workout` — a real card with a button, not a silent navigation the
/// instant the reply arrives. `plan`/`onStart` are nil wherever starting a
/// workout doesn't make sense (chat embedded in an already-active session);
/// the button just doesn't show there.
struct StartWorkoutCardRow: View {
    let payload: StartWorkoutCardPayload
    let plan: WeeklyPlan?
    let onStart: ((PlannedSession) -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(GymTheme.orange.opacity(0.16)).frame(width: 36, height: 36)
                Image(systemName: "play.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(GymTheme.orange)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(payload.sessionName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(GymTheme.label)
                Text("Ready to start")
                    .font(.footnote)
                    .foregroundStyle(GymTheme.label2)
            }
            Spacer(minLength: 0)
            if let session = plan?.sessions.first(where: { $0.id == payload.plannedSessionID }), let onStart {
                Button {
                    onStart(session)
                } label: {
                    Text("Start Now")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(GymTheme.orange, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}
