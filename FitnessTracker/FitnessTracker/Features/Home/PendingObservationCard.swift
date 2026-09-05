import SwiftUI
import SwiftData

/// One AI-derived, unconfirmed `ObservationModel` awaiting your review
/// (design spec §7). Accept flips `confirmed = true` in place; Dismiss
/// deletes the row outright — there is no "reject but keep" state, since a
/// rejected reading has no value to retain.
struct PendingObservationCard: View {
    let observation: ObservationModel
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COACH NOTICED")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(GymTheme.label3)

            Text("\(formattedValue) \(observation.unit) — \(displayKind)")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(GymTheme.label)

            HStack(spacing: 12) {
                Button {
                    onAccept()
                } label: {
                    Text("Confirm")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(GymTheme.lime, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    onDismiss()
                } label: {
                    Text("Dismiss")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(GymTheme.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(GymTheme.red.opacity(0.16), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var formattedValue: String {
        observation.value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", observation.value)
            : String(format: "%.1f", observation.value)
    }

    private var displayKind: String {
        switch observation.kind {
        case "bodyFatPercent": "Body fat"
        case "muscleMassKg": "Muscle mass"
        case "bodyweight": "Bodyweight"
        default: observation.kind
        }
    }
}
