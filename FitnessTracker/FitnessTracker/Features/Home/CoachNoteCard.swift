import SwiftUI
import SwiftData
import ExerciseCatalog
import LLMKit

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
    // Emphasize concrete training entities, not generic coaching prose. Keep
    // compound exercise names together so words like "pull" or "up" are never
    // accented when they are ordinary language.
    private static let trainingEntityPattern = try! NSRegularExpression(
        pattern: #"(?i)\b(?:weighted\s+walking\s+lunges?|walking\s+lunges?|archer\s+pull[- ]?ups?|assisted\s+chest\s+dips?|barbell\s+front\s+raises?|bench\s+press|deadlifts?|squats?|push[- ]?ups?|dips?|rows?|pull[- ]?downs?|overhead\s+press|upper[- ]body|lower[- ]body|core|traps?|quads?|hips?|lats?|chest|back|shoulders?|biceps?|triceps?|glutes?|calves?|delts?)\b"#
    )

    // A number is meaningful here only when it is attached to a training
    // unit or a ratio/range. This avoids coloring incidental prose such as
    // "two years" or isolated sentence numbers.
    private static let trainingMetricPattern = try! NSRegularExpression(
        pattern: #"(?i)(?<!\w)\d+(?:[.,]\d+)?(?:\s*[/–-]\s*\d+(?:[.,]\d+)?)?(?:\s*[- ]?(?:kg|kcal|lbs?|reps?|sessions?|weeks?|prs?|%|points?)\b|(?:\s+[a-z]+){1,2}\s+(?:kg|kcal|lbs?|reps?|sessions?|weeks?|prs?|%|points?)\b)"#
    )

    private static func emphasisRanges(in text: String) -> [Range<String.Index>] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = (trainingEntityPattern.matches(in: text, range: fullRange)
            + trainingMetricPattern.matches(in: text, range: fullRange))
            .map(\.range)
            .sorted { $0.location < $1.location }

        var accepted: [NSRange] = []
        for match in matches {
            guard let last = accepted.last else {
                accepted.append(match)
                continue
            }
            let lastEnd = NSMaxRange(last)
            if match.location < lastEnd {
                // Prefer the longer match when an entity and metric overlap.
                if NSMaxRange(match) - match.location > lastEnd - last.location {
                    accepted[accepted.count - 1] = match
                }
            } else {
                accepted.append(match)
            }
        }

        return accepted.compactMap { range in
            Range(range, in: text)
        }
    }

    /// Exposed internally for focused tests and future semantic renderers.
    static func emphasizedSegments(in text: String) -> [String] {
        emphasisRanges(in: text).map { String(text[$0]) }
    }

    static func highlighted(_ text: String, accent: Color, base: Color) -> Text {
        var result = Text("")
        var cursor = text.startIndex

        for range in emphasisRanges(in: text) {
            if cursor < range.lowerBound {
                let rendered = Text(String(text[cursor..<range.lowerBound])).foregroundStyle(base)
                result = Text("\(result)\(rendered)")
            }
            let rendered = Text(String(text[range])).bold().foregroundStyle(accent)
            result = Text("\(result)\(rendered)")
            cursor = range.upperBound
        }

        if cursor < text.endIndex {
            let rendered = Text(String(text[cursor..<text.endIndex])).foregroundStyle(base)
            result = Text("\(result)\(rendered)")
        }
        return result
    }
}

/// One proactive coach message (daily note, weekly recap, check-in reaction, or
/// pattern nudge). Tapping anywhere on the row expands long guidance.
struct CoachNoteCard: View {
    let note: CoachNoteModel

    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 36
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false
    @State private var showingReason = false
    @State private var textMetrics = NoteTextMetrics()

    private var friendlyKind: String {
        switch note.kindRaw {
        case "daily": return "Daily note"
        case "weekly": return "Weekly recap"
        case "checkin": return "Check-in"
        case "pattern": return "Pattern"
        case "analysis": return "Data insight"
        case "missedWeek": return "Missed sessions"
        default: return note.kindRaw
        }
    }

    private var symbolName: String {
        switch note.kindRaw {
        case "daily": return "sun.max.fill"
        case "weekly": return "calendar.badge.clock"
        case "checkin": return "heart.text.square.fill"
        case "pattern": return "chart.line.uptrend.xyaxis"
        case "analysis": return "chart.bar.xaxis"
        case "missedWeek": return "exclamationmark.triangle.fill"
        default: return "bubble.left.and.bubble.right.fill"
        }
    }

    private var symbolColor: Color {
        switch note.kindRaw {
        case "daily": return GymTheme.orange
        case "weekly": return GymTheme.blue
        case "checkin": return GymTheme.red
        case "pattern": return GymTheme.purple
        case "analysis": return GymTheme.lime
        case "missedWeek": return GymTheme.red
        default: return GymTheme.label2
        }
    }

    private var shouldOfferExpansion: Bool {
        textMetrics.full > textMetrics.collapsed + 1
    }

    private var highlightedNoteText: Text {
        CoachTextStyler.highlighted(note.text, accent: symbolColor, base: GymTheme.label2)
    }

    private var insightReason: String? {
        if let reason = note.reason, !reason.isEmpty { return reason }
        switch note.kindRaw {
        case "daily": return "Generated from today’s planned session and the latest recovery context available to your coach."
        case "weekly": return "Generated from last week’s completed sessions, PRs, and muscle coverage."
        case "analysis": return "Derived from your logged workouts and working-set history."
        case "checkin": return "Based on the sleep, soreness, and note details in your latest check-in."
        case "pattern": return "Based on a recurring pattern found in your training history."
        default: return nil
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbolName)
                    .font(.body.weight(.bold))
                    .foregroundStyle(symbolColor)
                    .frame(width: iconSize, height: iconSize)
                    .background(symbolColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(friendlyKind)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GymTheme.label)
                    Spacer(minLength: 4)
                    if let reason = insightReason {
                        Button {
                            showingReason = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(GymTheme.label3)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Why this insight")
                        .accessibilityHint("Shows the data used to form this insight")
                        .popover(isPresented: $showingReason) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Why this matters")
                                    .font(.headline)
                                Text(reason)
                                    .font(.subheadline)
                                    .foregroundStyle(GymTheme.label2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(16)
                            .presentationCompactAdaptation(.popover)
                            .frame(minWidth: 230, alignment: .leading)
                        }
                    }
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

                if shouldOfferExpansion {
                    HStack(spacing: 5) {
                        Text(isExpanded ? "Show less" : "Read full note")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.bold))
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(GymTheme.lime)
                    .frame(minHeight: 44, alignment: .leading)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture {
            guard shouldOfferExpansion else { return }
            let animation: Animation? = reduceMotion ? nil : .easeInOut(duration: 0.2)
            withAnimation(animation) { isExpanded.toggle() }
        }
        .accessibilityLabel(friendlyKind)
        .accessibilityValue(isExpanded ? "Expanded" : (shouldOfferExpansion ? "Collapsed, double tap to expand" : "No additional detail"))
        .accessibilityAddTraits(shouldOfferExpansion ? .isButton : [])
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
                .font(.body.weight(.bold))
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
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }
}

private enum CoachSection: String, CaseIterable, Identifiable {
    case insights
    case chat

    var id: String { rawValue }
    var title: String {
        switch self {
        case .insights: return "Insights"
        case .chat: return "Chat"
        }
    }
}

/// The Coach hub separates proactive guidance from the conversational
/// transcript. Insights is the default because the Home badge represents
/// unread proactive notes, not unread chat messages.
struct CoachInboxView: View {
    let catalog: CatalogStore
    let provider: (any LLMProvider)?
    let activeProfile: ProviderProfile?
    var onClose: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Query(sort: \CoachNoteModel.createdAt, order: .reverse)
    private var notes: [CoachNoteModel]
    @State private var selectedSection: CoachSection = .insights

    /// Keep the inbox useful at a glance: one current daily note, one current
    /// weekly recap, and the latest distinct reactive insight types.
    private var visibleNotes: [CoachNoteModel] {
        let calendar = Calendar.current
        var current: [CoachNoteModel] = []
        if let daily = notes.first(where: { $0.kindRaw == "daily" && calendar.isDateInToday($0.createdAt) }) {
            current.append(daily)
        }
        if let weekly = notes.first(where: {
            $0.kindRaw == "weekly" && calendar.isDate($0.createdAt, equalTo: .now, toGranularity: .weekOfYear)
        }) {
            current.append(weekly)
        }
        var seenTopics = Set<String>()
        for insight in notes where insight.kindRaw == "analysis" {
            let topic = insight.topicRaw ?? insight.id.uuidString
            guard seenTopics.insert(topic).inserted else { continue }
            current.append(insight)
            if seenTopics.count >= 4 { break }
        }
        for kind in ["checkin", "pattern"] {
            if let latest = notes.first(where: { $0.kindRaw == kind }) {
                current.append(latest)
            }
        }
        return current
    }

    private func markVisibleNotesRead() {
        let unread = visibleNotes.filter { $0.readAt == nil }
        guard !unread.isEmpty else { return }
        unread.forEach { $0.readAt = .now }
        _ = PersistenceReporter.attemptSave(context, operation: "persist context")
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Picker("Coach section", selection: $selectedSection) {
                ForEach(CoachSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if selectedSection == .insights {
                insightsContent
            } else {
                ChatView(
                    catalog: catalog,
                    provider: provider,
                    activeProfile: activeProfile,
                    showsHeader: false,
                    reservesTabBarSpace: false
                )
            }
        }
        .background(GymTheme.bg.ignoresSafeArea())
        .onAppear(perform: markVisibleNotesRead)
    }

    @ViewBuilder
    private var insightsContent: some View {
        if visibleNotes.isEmpty {
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

                    ForEach(visibleNotes) { note in
                        CoachNoteCard(note: note)
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Coach")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(GymTheme.label)

                Text(selectedSection == .insights ? "Your training guidance, in one place" : "Ask about your training")
                    .font(.subheadline)
                    .foregroundStyle(GymTheme.label2)
            }

            Spacer()

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
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
