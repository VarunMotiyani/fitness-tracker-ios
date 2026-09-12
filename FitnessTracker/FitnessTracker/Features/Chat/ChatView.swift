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
    @Query private var chatSummaries: [ChatSummaryModel]
    /// Both small, unfiltered — feeds `ChatCardView`'s suggestion-accept path
    /// and its live "already resolved?" check, mirroring what `HomeView`'s own
    /// `SuggestionCard` usage already queries.
    @Query private var pendingSuggestions: [PendingCoachSuggestion]
    @Query(sort: \StoredPlan.generatedAt, order: .reverse) private var storedPlans: [StoredPlan]
    @State private var draft = ""
    @State private var isSending = false
    /// Live "Checking your schedule…"-style status while a turn's tool-call
    /// loop runs, in place of a static "Coach is thinking…" for however many
    /// sequential calls a multi-step request actually takes.
    @StateObject private var progress = CoachProgress()
    @State private var errorText: String?
    @State private var lastSentText: String?
    @State private var lastReplyContext: String?
    @State private var replyTarget: ChatMessageModel?
    @State private var showScrollToLatest = false
    @State private var showClearConfirmation = false
    @State private var exportURL: URL?
    @State private var showExportShare = false
    @FocusState private var composerFocused

    @AppStorage("gym_accent_color") private var accentColorKey: String = "lime"
    @AppStorage("coach.activeConversationID") private var activeConversationID: String = "default"
    private var activeAccent: Color { GymTheme.accent(for: accentColorKey) }
    private var conversationMessages: [ChatMessageModel] {
        messages.filter { $0.conversationID == activeConversationID }
    }

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
                                if conversationMessages.isEmpty {
                                    emptyState
                                }

                                ForEach(conversationMessages) { message in
                                    messageBubble(message)
                                }

                                if isSending {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(activeAccent)
                                        Text(progress.stepText ?? "Coach is thinking…")
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
                            showScrollToLatest = isAwayFromLatest && conversationMessages.count > 1
                        })
                        .onAppear { scheduleScrollToLatest(using: proxy, animated: false) }
                        .onChange(of: conversationMessages.count) { _, _ in
                            scheduleScrollToLatest(using: proxy)
                        }
                        .onChange(of: conversationMessages.last?.id) { _, _ in
                            scheduleScrollToLatest(using: proxy)
                        }
                        .onChange(of: activeConversationID) { _, _ in
                            scheduleScrollToLatest(using: proxy, animated: false)
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
        .keyboardHandlingWithoutWindowPan()
        .confirmationDialog("Chat actions", isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button("Clear this chat", role: .destructive) { clearCurrentConversation() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the messages and summary from the current conversation.")
        }
        .sheet(isPresented: $showExportShare) {
            if let exportURL {
                ShareSheet(items: [exportURL])
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Coach")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(GymTheme.label)

                Text("Ask about your training")
                    .font(.subheadline)
                    .foregroundStyle(GymTheme.label2)
            }

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                chatUtilityLinks

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
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    /// Compact, familiar iOS actions in the title row. The system symbols are
    /// paired with accessibility labels; Clear is conditional so an empty
    /// conversation has no dead control.
    private var chatUtilityLinks: some View {
        HStack(spacing: 2) {
            Button {
                startNewConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(activeAccent)
                    .frame(width: 44, height: 44)
                    .background(GymTheme.surface, in: Circle().inset(by: 3))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start a new chat")
            .accessibilityHint("Opens a blank conversation and keeps this chat available")

            if !conversationMessages.isEmpty {
                // Export + Clear behind one overflow menu rather than two more
                // fixed 44pt circles — four of those plus the title text
                // overflowed the header row on-device, which is why Export
                // wasn't actually visible despite being in the view tree.
                Menu {
                    Button {
                        exportChat()
                    } label: {
                        Label("Export Chat", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Label("Clear Chat", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(activeAccent)
                        .frame(width: 44, height: 44)
                        .background(GymTheme.surface, in: Circle().inset(by: 3))
                }
                .accessibilityLabel("More chat actions")
            }
        }
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
        guard let last = conversationMessages.last else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
        showScrollToLatest = false
    }

    /// Wait for the message insertion transaction to lay out before asking
    /// ScrollViewReader to resolve the new row's ID. Calling scrollTo in the
    /// same update that inserts a message can be ignored or visibly lag one
    /// reply behind.
    private func scheduleScrollToLatest(using proxy: ScrollViewProxy, animated: Bool = true) {
        Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            scrollToLatest(using: proxy, animated: animated)
        }
    }

    private func startNewConversation() {
        let oldConversationID = activeConversationID
        activeConversationID = UUID().uuidString
        draft = ""
        replyTarget = nil
        errorText = nil
        lastSentText = nil
        lastReplyContext = nil
        composerFocused = false

        Task { @MainActor in
            await ChatMemoryExtractor(
                context: context,
                provider: provider,
                activeProfile: activeProfile,
                conversationID: oldConversationID
            ).extractMemoriesIfNeeded()
        }
    }

    private func clearCurrentConversation() {
        for message in messages where message.conversationID == activeConversationID {
            context.delete(message)
        }
        for summary in chatSummaries where summary.conversationID == activeConversationID {
            context.delete(summary)
        }
        _ = PersistenceReporter.attemptSave(context, operation: "clear chat conversation")
        draft = ""
        replyTarget = nil
        errorText = nil
        lastSentText = nil
        lastReplyContext = nil
        composerFocused = false
    }

    private func exportChat() {
        guard let url = ChatTranscriptExporter.writeToTempFile(conversationMessages) else {
            errorText = "Couldn't export chat."
            return
        }
        exportURL = url
        showExportShare = true
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
        progress.stepText = nil

        Task { @MainActor in
            let coordinator = AskCoachCoordinator(catalog: catalog, context: context, provider: provider,
                                                  activeProfile: activeProfile,
                                                  conversationID: activeConversationID,
                                                  progress: progress)
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

/// The transcript's reply gesture must never steal a predominantly vertical
/// scroll. The policy is kept pure so the diagonal-drag regression is covered
/// without needing to drive UIKit gesture recognizers in a test.
enum ChatGesturePolicy {
    static func shouldReply(width: CGFloat, height: CGFloat, horizontalIntent: Bool) -> Bool {
        horizontalIntent && width > 56 && width > abs(height)
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

    /// The coach's replies routinely include `**bold**` and numbered lists
    /// (real examples from device logs: "1. **2026-09-13 (Sunday)** –
    /// Push-focused…") — `Text(String)` never parses that, so it rendered as
    /// literal asterisks/hashes cluttering every reply. `.full` handles both
    /// inline emphasis and list structure; a message that fails to parse
    /// (stray markdown-like characters in ordinary prose) falls back to the
    /// original plain text rather than showing nothing.
    private func renderedLine(_ line: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        if let parsed = try? AttributedString(markdown: line, options: options) {
            return parsed
        }
        return AttributedString(line)
    }

    /// One `Text` per source line rather than one giant block — `Text`'s own
    /// markdown rendering parses list/bold syntax correctly but still lays
    /// everything out as one dense paragraph with no breathing room between
    /// list items, which is exactly what read as "just a wall of text."
    /// Splitting gives each numbered item/paragraph its own line with real
    /// spacing, without needing a full markdown block-layout engine.
    private var paragraphs: [AttributedString] {
        message.text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { renderedLine(String($0).trimmingCharacters(in: .whitespaces)) }
    }

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

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(GymTheme.label)
                            .lineSpacing(3)
                    }
                }
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
        // A UIKit directional pan rejects vertical motion in
        // `gestureRecognizerShouldBegin`, so the enclosing ScrollView owns
        // the touch stream immediately instead of competing with it.
        .overlay {
            HorizontalReplyGestureView(
                onChanged: { translation in
                    horizontalOffset = translation
                },
                onEnded: { shouldReply in
                    let animation: Animation? = reduceMotion ? nil : .easeOut(duration: 0.2)
                    withAnimation(animation) { horizontalOffset = 0 }
                    if shouldReply { onReply() }
                }
            )
        }
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

/// Direction-locked reply recognizer. SwiftUI's DragGesture cannot fail early
/// based on axis, which lets a child bubble compete with a vertical ScrollView
/// drag. UIKit's `shouldBegin` gives the scroll view an unambiguous winner.
private struct HorizontalReplyGestureView: UIViewRepresentable {
    let onChanged: (CGFloat) -> Void
    let onEnded: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.cancelsTouchesInView = false
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        context.coordinator.pan = pan
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGFloat) -> Void
        var onEnded: (Bool) -> Void
        weak var pan: UIPanGestureRecognizer?

        init(onChanged: @escaping (CGFloat) -> Void, onEnded: @escaping (Bool) -> Void) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return velocity.x > 0 && abs(velocity.x) > abs(velocity.y)
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            switch gesture.state {
            case .changed:
                onChanged(min(max(translation.x, 0), 92))
            case .ended:
                onEnded(ChatGesturePolicy.shouldReply(
                    width: translation.x,
                    height: translation.y,
                    horizontalIntent: true
                ))
            case .cancelled, .failed:
                onEnded(false)
            default:
                break
            }
        }
    }
}
