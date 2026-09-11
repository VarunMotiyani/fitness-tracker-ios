import SwiftUI
import SwiftData
import ExerciseCatalog
import LLMKit

/// Ask Coach's chat screen (design spec §3). Reachable as its own tab
/// (`RootView`'s `.coach` case) and as a `.sheet` from Home/Session/Plan's
/// toolbar. `onClose` is only set for the sheet presentations — the tab
/// embedding has no dismiss affordance of its own, matching how
/// `HomeView`/`PlanView` are embedded without a wrapping `NavigationStack`.
struct ChatView: View {
    let catalog: CatalogStore
    let provider: (any LLMProvider)?
    let activeProfile: ProviderProfile?
    var onClose: (() -> Void)? = nil
    var showsHeader: Bool = true
    /// Sheet/tab presentations reserve the bottom tab-bar inset; embedded
    /// Coach hub chat should use the full sheet height instead.
    var reservesTabBarSpace: Bool = true

    @Environment(\.modelContext) private var context
    @Query(sort: \ChatMessageModel.timestamp) private var messages: [ChatMessageModel]
    @State private var draft: String = ""
    @State private var isSending = false
    @State private var errorText: String?
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
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if messages.isEmpty {
                                Text("Ask your coach about recovery, muscle balance, or your training history.")
                                    .font(.subheadline)
                                    .foregroundStyle(GymTheme.label3)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.top, 24)
                            }
                            ForEach(messages) { message in
                                messageBubble(message)
                            }
                            if isSending {
                                Text("Coach is thinking…")
                                    .font(.footnote)
                                    .foregroundStyle(GymTheme.label3)
                            }
                            if let errorText {
                                Text(errorText)
                                    .font(.footnote)
                                    .foregroundStyle(GymTheme.red)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(GymTheme.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                inputBar
            }
        }
        .background(GymTheme.bg.ignoresSafeArea())
        // Never swipe-away a typed-but-unsent question.
        .interactiveDismissDisabled(!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Coach")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(GymTheme.label)

                Text("Ask about your training")
                    .font(.body.weight(.regular))
                    .foregroundStyle(Color(white: 0.65))
            }

            Spacer()

            if let onClose {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(white: 0.70))
                        .frame(width: 44, height: 44)
                        .background(GymTheme.surface, in: Circle().inset(by: 3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close coach chat")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Messages

    @ViewBuilder
    private func messageBubble(_ message: ChatMessageModel) -> some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 40) }
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(GymTheme.label)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    message.role == "user" ? activeAccent.opacity(0.22) : GymTheme.surface2,
                    in: RoundedRectangle(cornerRadius: 14)
                )
            if message.role == "assistant" { Spacer(minLength: 40) }
        }
        .id(message.id)
    }

    // MARK: - Input

    @ViewBuilder
    private var inputBar: some View {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .padding(.bottom, reservesTabBarSpace && onClose == nil ? 90 : 0)
        .background(GymTheme.bgElevated)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending, let provider else { return }
        draft = ""
        isSending = true
        errorText = nil
        Task {
            let coordinator = AskCoachCoordinator(catalog: catalog, context: context, provider: provider, activeProfile: activeProfile)
            let result = await coordinator.send(text)
            if result.isError { errorText = result.text }
            isSending = false
        }
    }
}
