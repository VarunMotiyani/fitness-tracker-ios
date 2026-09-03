import SwiftUI
import FitnessDomain
import Metrics

public struct SessionNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding public var sessionNote: String

    public init(sessionNote: Binding<String>) {
        self._sessionNote = sessionNote
    }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Session Reflection & Notes")
                    .font(.headline)
                    .foregroundStyle(GymTheme.label)

                TextEditor(text: $sessionNote)
                    .frame(minHeight: 140)
                    .padding(8)
                    .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 10))

                HStack {
                    Spacer()
                    Text("\(sessionNote.count)/\(Notes.maxLength)")
                        .font(.caption)
                        .foregroundStyle(sessionNote.count > Notes.maxLength ? GymTheme.red : GymTheme.label3)
                }

                Spacer()
            }
            .padding(16)
            .background(GymTheme.bg.ignoresSafeArea())
            .navigationTitle("Workout Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        sessionNote = Notes.clamp(sessionNote)
                        dismiss()
                    }
                }
            }
        }
    }
}
