import SwiftUI
import SwiftData

/// One proactive coach message (daily note, weekly recap, check-in reaction, or
/// pattern nudge) awaiting your acknowledgment. `readAt == nil` means unread.
/// Tapping "Got it" sets `readAt = .now` and persists via the model context.
struct CoachNoteCard: View {
    let note: CoachNoteModel
    let onDismiss: () -> Void

    private var friendlyKind: String {
        switch note.kindRaw {
        case "daily": return "Daily note"
        case "weekly": return "Weekly recap"
        case "checkin": return "Check-in"
        case "pattern": return "Pattern"
        default: return note.kindRaw
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COACH · \(friendlyKind.uppercased())")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(GymTheme.label3)

            Text(note.text)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(GymTheme.label)

            Button {
                onDismiss()
            } label: {
                Text("Got it")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(GymTheme.lime, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GymTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}
