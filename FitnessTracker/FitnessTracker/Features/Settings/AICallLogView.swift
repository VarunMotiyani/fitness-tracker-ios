import SwiftUI
import SwiftData

/// Every `AICallRecord` behind the Settings cost summary, most recent first —
/// so "$0.62 this month" is auditable down to which feature made which call,
/// not just a trust-me total.
struct AICallLogView: View {
    @Query(sort: \AICallRecord.timestamp, order: .reverse) private var calls: [AICallRecord]
    @Query private var allProviderProfiles: [ProviderProfile]

    private var groupedByDay: [(day: Date, calls: [AICallRecord])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: calls) { cal.startOfDay(for: $0.timestamp) }
        return grouped.keys.sorted(by: >).map { day in
            (day: day, calls: grouped[day]!.sorted { $0.timestamp > $1.timestamp })
        }
    }

    var body: some View {
        List {
            if calls.isEmpty {
                ContentUnavailableView(
                    "No AI calls yet", systemImage: "sparkles",
                    description: Text("Every coach reply, plan generation, and background check will show up here."))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(groupedByDay, id: \.day) { group in
                    Section {
                        ForEach(group.calls) { call in
                            AICallLogRow(call: call,
                                        billedCost: AICallRecord.billedCost(for: call, profiles: allProviderProfiles))
                        }
                    } header: {
                        Text(group.day.formatted(date: .abbreviated, time: .omitted))
                    }
                }
            }
        }
        .navigationTitle("AI Call History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AICallLogRow: View {
    let call: AICallRecord
    let billedCost: Double

    private static let labels: [String: (title: String, icon: String)] = [
        "askCoach": ("Ask Coach", "bubble.left.and.bubble.right.fill"),
        "plan": ("Plan Generation", "calendar"),
        "finalize": ("Session Finalize", "flame.fill"),
        "memoryKeeper": ("Memory Keeper", "brain.head.profile"),
        "chatSummarize": ("Chat Summary", "text.line.first.and.arrowtriangle.forward"),
        "dailyNarration": ("Daily Narration", "sun.max.fill"),
        "weeklySummary": ("Weekly Summary", "calendar.badge.clock"),
        "patternNudge": ("Pattern Nudge", "repeat"),
    ]

    private var display: (title: String, icon: String) {
        Self.labels[call.callType] ?? (call.callType, "sparkles")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: display.icon)
                .font(.body)
                .foregroundStyle(call.success ? GymTheme.violet : GymTheme.red)
                .frame(width: 22)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(display.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(GymTheme.label)
                    if call.usedFallback {
                        badge("fallback", color: GymTheme.orange)
                    }
                    if !call.success {
                        badge("failed", color: GymTheme.red)
                    }
                }
                Text("\(call.providerDisplayName) · \(call.modelID)")
                    .font(.caption)
                    .foregroundStyle(GymTheme.label3)
                Text(tokenSummary)
                    .font(.caption2)
                    .foregroundStyle(GymTheme.label4)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(CostSummary.display(billedCost))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GymTheme.label)
                Text(call.timestamp, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(GymTheme.label4)
                if call.durationMs > 0 {
                    Text(durationDisplay)
                        .font(.caption2)
                        .foregroundStyle(call.durationMs > 8000 ? GymTheme.orange : GymTheme.label4)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// 0 shows as nothing (row predates this field, see `AICallRecord.durationMs`'s
    /// doc comment) rather than a misleading "0.0s".
    private var durationDisplay: String {
        String(format: "%.1fs", Double(call.durationMs) / 1000)
    }

    private var tokenSummary: String {
        var parts = ["\(call.inputTokens) in", "\(call.outputTokens) out"]
        if call.cachedTokens > 0 { parts.append("\(call.cachedTokens) cached") }
        return parts.joined(separator: " · ")
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
