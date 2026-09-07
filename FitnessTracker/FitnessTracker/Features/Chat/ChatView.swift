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

    @Environment(\.modelContext) private var context
    @Query(sort: \ChatMessageModel.timestamp) private var messages: [ChatMessageModel]
    @State private var draft: String = ""
    @State private var isSending = false
    @State private var errorText: String?

    @AppStorage("gym_accent_color") private var accentColorKey: String = "lime"
    private var activeAccent: Color { GymTheme.accent(for: accentColorKey) }

    var body: some View {
        VStack(spacing: 0) {
            headerSection

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
                                    .font(.system(size: 14))
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
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color(white: 0.65))
            }

            Spacer()

            if let onClose {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(white: 0.70))
                        .frame(width: 38, height: 38)
                        .background(GymTheme.surface, in: Circle())
                }
                .buttonStyle(.plain)
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
                .font(.system(size: 15))
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
                .font(.system(size: 15))
                .foregroundStyle(GymTheme.label)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                .lineLimit(1...4)

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 36, height: 36)
                    .background(
                        (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                            ? GymTheme.surface3 : activeAccent,
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .padding(.bottom, onClose == nil ? 90 : 0)
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
