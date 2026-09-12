import SwiftUI
import SwiftData
import UIKit
import FitnessDomain
import ExerciseCatalog
import LLMKit

/// Ask Coach's conversation surface. It is presented from Home, Plan, and an
/// active session, or embedded in the Coach hub beside proactive Insights.
/// The transcript owns scrolling; the composer stays anchored above the safe
/// area and presented sheets are closed explicitly with their top X button.
struct ChatView: View {
    let catalog: CatalogStore
    let provider: (any LLMProvider)?
    let activeProfile: ProviderProfile?
    var onClose: (() -> Void)? = nil
    var showsHeader: Bool = true
    /// Needed to resolve a `start_workout` tool call's plannedSessionID back
    /// into a real `PlannedSession` — nil where starting a workout doesn't
    /// make sense (e.g. the chat embedded in an already-active session).
    var plan: WeeklyPlan? = nil
    var onStartSession: ((PlannedSession) -> Void)? = nil
    /// Sheet/tab presentations reserve the bottom tab-bar inset; embedded
    /// Coach hub chat should use the full sheet height instead.
    var reservesTabBarSpace: Bool = true

    @Environment(\.modelContext) private var context
    @Query(sort: \ChatMessageModel.timestamp) private var messages: [ChatMessageModel]
    /// Both small, unfiltered — feeds `ChatCardView`'s suggestion-accept path
    /// and its live "already resolved?" check, mirroring what `HomeView`'s own
    /// `SuggestionCard` usage already queries.
    @Query private var pendingSuggestions: [PendingCoachSuggestion]
    @Query(sort: \StoredPlan.generatedAt, order: .reverse) private var storedPlans: [StoredPlan]
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorText: String?
    @State private var lastSentText: String?
    @State private var lastReplyContext: String?
    @State private var replyTarget: ChatMessageModel?
    @State private var showScrollToLatest = false
    @FocusState private var composerFocused

    @AppStorage("gym_accent_color") private var accentColorKey: String = "lime"
    private var activeAccent: Color { GymTheme.accent(for: accentColorKey) }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                headerSection
            }

            if provider == nil {
                ContentUnavailableView(
                    "Set up an AI provider in Settings to talk to your coach",
                    systemImage: "bubble.left.and.bubble.right"
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ZStack(alignment: .bottomTrailing) {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                if messages.isEmpty {
                                    emptyState
                                }

                                ForEach(messages) { message in
                                    messageBubble(message)
                                }

                                if isSending {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(activeAccent)
                                        Text("Coach is thinking…")
                                    }
                                    .font(.footnote)
                                    .foregroundStyle(GymTheme.label3)
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel("Coach is thinking")
                                }

                                if let errorText {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(errorText)
                                            .font(.footnote)
                                            .foregroundStyle(GymTheme.red)
                                            .fixedSize(horizontal: false, vertical: true)

                                        if let lastSentText {
                                            Button("Retry") {
                                                send(lastSentText)
                                            }
                                            .font(.footnote.weight(.semibold))
                                            .buttonStyle(.bordered)
                                            .tint(activeAccent)
                                            .accessibilityHint("Resend your last message")
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(GymTheme.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 24)
                        }
                        // Keep the keyboard gesture on the actual transcript
                        // scroll view. The outer chat stack cannot reliably
                        // forward interactive dismissal through nested message
                        // gestures on iPhone.
                        .scrollDismissesKeyboard(.interactively)
                        .onScrollGeometryChange(for: Bool.self, of: { geometry in
                            let visibleBottom = geometry.contentOffset.y + geometry.containerSize.height
                            let contentBottom = geometry.contentSize.height + geometry.contentInsets.bottom
                            return contentBottom - visibleBottom > 80
                        }, action: { _, isAwayFromLatest in
                            showScrollToLatest = isAwayFromLatest && messages.count > 1
                        })
                        .onAppear { scrollToLatest(using: proxy, animated: false) }
                        .onChange(of: messages.count) { _, _ in
                            scrollToLatest(using: proxy)
                        }

                        if showScrollToLatest {
                            Button {
                                scrollToLatest(using: proxy)
                            } label: {
                                Image(systemName: "arrow.down")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(GymTheme.label)
                                    .frame(width: 44, height: 44)
                                    .background(GymTheme.surface3, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 18)
                            .padding(.bottom, 12)
                            .accessibilityLabel("Jump to latest message")
                        }
                    }
                }

                inputBar
            }
        }
        .background(GymTheme.bg.ignoresSafeArea())
        // Chat is an intentional destination: only the top X button closes it.
        // This also prevents a downward transcript drag from dismissing the
        // sheet while preserving interactive keyboard dismissal on the scroll
        // view above.
        .interactiveDismissDisabled(true)
        .keyboardHandling()
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Coach")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(GymTheme.label)

                Text("Ask about your training")
                    .font(.subheadline)
                    .foregroundStyle(GymTheme.label2)
            }

            Spacer()

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GymTheme.label2)
                        .frame(width: 44, height: 44)
                        .background(GymTheme.surface, in: Circle().inset(by: 3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close coach chat")
                .accessibilityHint("Returns to the previous screen")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Messages

    @ViewBuilder
    private func messageBubble(_ message: ChatMessageModel) -> some View {
        if message.cardKind != nil {
            ChatCardView(
                message: message,
                catalog: catalog,
                pendingSuggestions: pendingSuggestions,
                storedPlan: storedPlans.first,
                plan: plan,
                onStartSession: onStartSession
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(message.id)
        } else {
            CoachChatBubble(
                message: message,
                accent: activeAccent,
                onReply: { beginReply(to: message) },
                onCopy: { UIPasteboard.general.string = message.text }
            )
            .id(message.id)
        }
    }

    // MARK: - Composer

    @ViewBuilder
    private var inputBar: some View {
        VStack(spacing: 8) {
            if let replyTarget {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(activeAccent)
                        .frame(width: 3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Replying to \(replyTarget.role == "user" ? "yourself" : "Coach")")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(activeAccent)
                        Text(replyTarget.text)
                            .font(.caption)
                            .foregroundStyle(GymTheme.label2)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 4)

                    Button {
                        self.replyTarget = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(GymTheme.label3)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel reply")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 10) {
                TextField("Ask your coach…", text: $draft, axis: .vertical)
                    .font(.subheadline)
                    .foregroundStyle(GymTheme.label)
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit { send() }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                    .lineLimit(1...4)
                    .accessibilityLabel("Message to coach")

                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                        .background(
                            (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                                ? GymTheme.surface3 : activeAccent,
                            in: Circle().inset(by: 4)
                        )
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                .accessibilityLabel("Send message")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .padding(.bottom, reservesTabBarSpace && onClose == nil ? 90 : 0)
        .background(GymTheme.bgElevated)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.bubble.fill")
                .font(.title2)
                .foregroundStyle(activeAccent)
                .accessibilityHidden(true)

            Text("Ask your coach anything about training, recovery, or progress.")
                .font(.subheadline)
                .foregroundStyle(GymTheme.label2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["What should I train today?", "How is my recovery?", "Find a weak point"], id: \.self) { prompt in
                        Button(prompt) {
                            draft = prompt
                            composerFocused = true
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(activeAccent)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 40)
                        .background(activeAccent.opacity(0.12), in: Capsule())
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
    }

    private func beginReply(to message: ChatMessageModel) {
        replyTarget = message
        composerFocused = true
    }

    private func scrollToLatest(using proxy: ScrollViewProxy, animated: Bool = true) {
        guard let last = messages.last else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
        showScrollToLatest = false
    }

    private func send(_ resentText: String? = nil) {
        let text = (resentText ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending, provider != nil else { return }
        let replyContext = resentText == nil ? replyTarget?.text : lastReplyContext
        draft = ""
        lastSentText = text
        lastReplyContext = replyContext
        replyTarget = nil
        isSending = true
        errorText = nil

        Task { @MainActor in
            let coordinator = AskCoachCoordinator(catalog: catalog, context: context, provider: provider, activeProfile: activeProfile)
            let result = await coordinator.send(text, replyingTo: replyContext)
            if result.isError {
                errorText = result.text
            } else {
                lastSentText = nil
                lastReplyContext = nil
            }
            // No longer auto-navigates on `startSessionID` — `start_workout`
            // now renders a real card with its own "Start Now" button
            // (`StartWorkoutCardRow`), so leaving the chat happens only when
            // the athlete actually taps it, not the instant the reply arrives.
            isSending = false
        }
    }
}

/// A message row with the interaction conventions users expect from modern
/// chat apps: swipe right to reply, long-press for copy/reply, and explicit
/// role semantics for assistive technologies.
private struct CoachChatBubble: View {
    let message: ChatMessageModel
    let accent: Color
    let onReply: () -> Void
    let onCopy: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var horizontalOffset: CGFloat = 0

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        ZStack(alignment: .leading) {
            if horizontalOffset > 0 {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 36)
                    .opacity(min(horizontalOffset / 56, 1))
            }

            HStack {
                if isUser { Spacer(minLength: 40) }

                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(GymTheme.label)
                    .lineSpacing(2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        isUser ? accent.opacity(0.22) : GymTheme.surface2,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                    .offset(x: horizontalOffset)

                if !isUser { Spacer(minLength: 40) }
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 16)
                .onChanged { value in
                    guard value.translation.width > abs(value.translation.height) else { return }
                    horizontalOffset = min(max(value.translation.width, 0), 92)
                }
                .onEnded { value in
                    let shouldReply = value.translation.width > 56
                    let animation: Animation? = reduceMotion ? nil : .easeOut(duration: 0.2)
                    withAnimation(animation) { horizontalOffset = 0 }
                    if shouldReply { onReply() }
                }
        )
        .contextMenu {
            Button(action: onReply) {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }
            Button(action: onCopy) {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isUser ? "You" : "Coach")
        .accessibilityValue(message.text)
        .accessibilityHint("Swipe right or use the context menu to reply")
    }
}
