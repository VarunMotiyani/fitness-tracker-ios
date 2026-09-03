import SwiftUI
import FitnessDomain
import Metrics

public struct ExerciseNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let exerciseName: String
    public let planNote: String?
    public let standingNote: String?
    public let pinnedNote: (note: String, date: Date)?
    
    @Binding public var todayNote: String
    @Binding public var notePin: Bool

    public init(
        exerciseName: String,
        planNote: String?,
        standingNote: String?,
        pinnedNote: (note: String, date: Date)?,
        todayNote: Binding<String>,
        notePin: Binding<Bool>
    ) {
        self.exerciseName = exerciseName
        self.planNote = planNote
        self.standingNote = standingNote
        self.pinnedNote = pinnedNote
        self._todayNote = todayNote
        self._notePin = notePin
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let planNote, !planNote.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Plan Instruction", systemImage: "sparkles")
                                .font(.caption.bold())
                                .foregroundStyle(GymTheme.orange)
                            Text(planNote)
                                .font(.subheadline)
                                .foregroundStyle(GymTheme.label)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 10))
                    }

                    if let standingNote, !standingNote.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Standing Note", systemImage: "info.circle")
                                .font(.caption.bold())
                                .foregroundStyle(GymTheme.sky)
                            Text(standingNote)
                                .font(.subheadline)
                                .foregroundStyle(GymTheme.label)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 10))
                    }

                    if let pinnedNote {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Pinned from Previous Session", systemImage: "pin.fill")
                                .font(.caption.bold())
                                .foregroundStyle(GymTheme.violet)
                            Text(pinnedNote.note)
                                .font(.subheadline)
                                .foregroundStyle(GymTheme.label)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Today's Note")
                            .font(.headline)
                            .foregroundStyle(GymTheme.label)

                        TextEditor(text: $todayNote)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(GymTheme.surface2, in: RoundedRectangle(cornerRadius: 10))

                        Toggle(isOn: $notePin) {
                            Label("Pin note for next time", systemImage: "pin")
                                .font(.subheadline)
                                .foregroundStyle(GymTheme.label)
                        }
                        .tint(GymTheme.green)
                        .padding(.top, 4)
                    }
                }
                .padding(16)
            }
            .background(GymTheme.bg.ignoresSafeArea())
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        todayNote = Notes.clamp(todayNote)
                        dismiss()
                    }
                }
            }
        }
    }
}
