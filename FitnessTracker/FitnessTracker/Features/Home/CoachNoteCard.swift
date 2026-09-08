import SwiftUI
import SwiftData

private struct NoteTextMetrics: Equatable {
    var collapsed: CGFloat = 0
    var full: CGFloat = 0
}

private struct NoteTextMetricsPreferenceKey: PreferenceKey {
    static let defaultValue = NoteTextMetrics()

    static func reduce(value: inout NoteTextMetrics, nextValue: () -> NoteTextMetrics) {
        let next = nextValue()
        value.collapsed = max(value.collapsed, next.collapsed)
        value.full = max(value.full, next.full)
    }
}

enum CoachTextStyler {
    static let emphasisWords: Set<String> = [
        "today", "today's", "todays", "next", "target", "stay", "avoid", "protect",
        "safety", "limit", "start", "before", "after", "recovery", "rest", "focus",
        "reps", "rep", "kg", "archer", "pull", "push", "up", "dips", "raise",
        "lunges", "squat", "bench", "deadlift", "lats", "back", "chest", "shoulders",
        "biceps", "triceps", "quads", "glutes", "calves", "delts", "sessions",
        "session", "streak", "records", "record", "week", "weeks"
    ]

    static func highlighted(_ text: String, accent: Color, base: Color) -> Text {
        let tokens = text.split(separator: " ", omittingEmptySubsequences: false)
        return tokens.enumerated().reduce(Text("")) { result, part in
            let token = String(part.element)
            let normalized = token
                .trimmingCharacters(in: .punctuationCharacters.union(.symbols))
                .lowercased()
            let containsNumber = token.contains { $0.isNumber }
            let isEmphasized = containsNumber || emphasisWords.contains(normalized)
            let rendered = Text(token)
                .bold(isEmphasized)
                .foregroundStyle(isEmphasized ? accent : base)
            let separator = part.offset == tokens.count - 1 ? "" : " "
            return Text("\(result)\(rendered)\(separator)")
        }
    }
}

/// One proactive coach message (daily note, weekly recap, check-in reaction, or
/// pattern nudge) awaiting your acknowledgment. `readAt == nil` means unread.
/// Tapping "Dismiss" sets `readAt = .now` and persists via the model context.
struct CoachNoteCard: View {
    let note: CoachNoteModel
    let onDismiss: () -> Void

    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 36
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false
    @State private var textMetrics = NoteTextMetrics()

    private var friendlyKind: String {
        switch note.kindRaw {
        case "daily": return "Daily note"
        case "weekly": return "Weekly recap"
        case "checkin": return "Check-in"
        case "pattern": return "Pattern"
        default: return note.kindRaw
        }
    }

    private var symbolName: String {
        switch note.kindRaw {
        case "daily": return "sun.max.fill"
        case "weekly": return "calendar.badge.clock"
        case "checkin": return "heart.text.square.fill"
        case "pattern": return "chart.line.uptrend.xyaxis"
        default: return "bubble.left.and.bubble.right.fill"
        }
    }

    private var symbolColor: Color {
        switch note.kindRaw {
        case "daily": return GymTheme.orange
        case "weekly": return GymTheme.blue
        case "checkin": return GymTheme.red
        case "pattern": return GymTheme.purple
        default: return GymTheme.label2
        }
    }

    private var shouldOfferExpansion: Bool {
        textMetrics.full > textMetrics.collapsed + 1
    }

    private var highlightedNoteText: Text {
        CoachTextStyler.highlighted(note.text, accent: symbolColor, base: GymTheme.label2)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(symbolColor)
                .frame(width: iconSize, height: iconSize)
                .background(symbolColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(friendlyKind)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GymTheme.label)
                }

                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(symbolColor.opacity(0.75))
                        .frame(width: 3)

                    highlightedNoteText
                        .font(.body)
                        .foregroundStyle(GymTheme.label2)
                        .lineSpacing(4)
                        .lineLimit(isExpanded ? nil : 4)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(
                            highlightedNoteText
                                .font(.body)
                                .lineLimit(4)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                                .opacity(0)
                                .accessibilityHidden(true)
                                .background(GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: NoteTextMetricsPreferenceKey.self,
                                        value: NoteTextMetrics(collapsed: proxy.size.height)
                                    )
                                })
                        )
                        .overlay(
                            highlightedNoteText
                                .font(.body)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                                .opacity(0)
                                .accessibilityHidden(true)
                                .background(GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: NoteTextMetricsPreferenceKey.self,
                                        value: NoteTextMetrics(full: proxy.size.height)
                                    )
                                })
                        )
                }

                HStack(spacing: 8) {
                    if shouldOfferExpansion {
                        Button {
                            let animation: Animation? = reduceMotion ? nil : .easeInOut(duration: 0.2)
                            withAnimation(animation) { isExpanded.toggle() }
                        } label: {
                            HStack(spacing: 5) {
                                Text(isExpanded ? "Show less" : "Read full note")
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption.weight(.bold))
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(GymTheme.lime)
                            .frame(minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isExpanded ? "Collapse note" : "Expand note")
                        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                    }

                    Spacer(minLength: 8)

                    Button("Dismiss", action: onDismiss)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(minWidth: 64, minHeight: 44)
                        .padding(.horizontal, 8)
                        .background(GymTheme.lime, in: Capsule())
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 16))
        .onPreferenceChange(NoteTextMetricsPreferenceKey.self) { metrics in
            guard metrics != textMetrics else { return }
            textMetrics = metrics
        }
    }
}

/// A compact Home preview for the latest coach insight. The full note history
/// remains available from Coach, so Home can keep the workout action primary.
struct CoachInsightPreview: View {
    let note: CoachNoteModel
    let onOpenCoach: () -> Void
    let onDismiss: () -> Void

    private var symbolName: String {
        switch note.kindRaw {
        case "daily": return "sun.max.fill"
        case "weekly": return "calendar.badge.clock"
        case "checkin": return "heart.text.square.fill"
        case "pattern": return "chart.line.uptrend.xyaxis"
        default: return "bubble.left.and.bubble.right.fill"
        }
    }

    private var symbolColor: Color {
        switch note.kindRaw {
        case "daily": return GymTheme.orange
        case "weekly": return GymTheme.blue
        case "checkin": return GymTheme.red
        case "pattern": return GymTheme.purple
        default: return GymTheme.label2
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(symbolColor)
                .frame(width: 36, height: 36)
                .background(symbolColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Button(action: onOpenCoach) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Coach insight")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(GymTheme.label)

                            Text("NEW")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(GymTheme.lime)
                                .tracking(0.7)

                            Spacer(minLength: 4)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(GymTheme.label3)
                                .accessibilityHidden(true)
                        }

                        CoachTextStyler.highlighted(note.text, accent: symbolColor, base: GymTheme.label2)
                            .font(.subheadline)
                            .foregroundStyle(GymTheme.label2)
                            .lineSpacing(2)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View coach insight")

                HStack(spacing: 8) {
                    Button("View insight", action: onOpenCoach)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(GymTheme.lime)
                        .frame(minHeight: 44, alignment: .leading)
                        .buttonStyle(.plain)

                    Spacer(minLength: 8)

                    Button("Dismiss", action: onDismiss)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(GymTheme.label3)
                        .frame(minHeight: 44, alignment: .trailing)
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }
}

/// Dedicated destination for proactive guidance. Chat remains a separate
/// surface so reading a coach brief never places a message composer beneath it.
struct CoachInboxView: View {
    var onClose: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Query(sort: \CoachNoteModel.createdAt, order: .reverse)
    private var notes: [CoachNoteModel]

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            if notes.isEmpty {
                ContentUnavailableView(
                    "No coach insights yet",
                    systemImage: "sun.max",
                    description: Text("Your personalized guidance will appear here.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        Text("Your guidance")
                            .font(.headline)
                            .foregroundStyle(GymTheme.label)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(notes) { note in
                            CoachNoteCard(note: note, onDismiss: {
                                note.readAt = .now
                                try? context.save()
                            })
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(GymTheme.bg.ignoresSafeArea())
    }

    @ViewBuilder
    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Coach insights")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(GymTheme.label)

                Text("Your training guidance, in one place")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color(white: 0.65))
            }

            Spacer()

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(white: 0.70))
                        .frame(width: 44, height: 44)
                        .background(GymTheme.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close coach insights")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}
