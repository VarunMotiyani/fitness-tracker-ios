import SwiftUI

public struct DayAssignSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let weekdayName: String
    public let routines: [RoutineDraft]
    public let currentRoutineID: UUID?
    public let onAssign: (UUID?) -> Void

    public init(
        weekdayName: String,
        routines: [RoutineDraft],
        currentRoutineID: UUID?,
        onAssign: @escaping (UUID?) -> Void
    ) {
        self.weekdayName = weekdayName
        self.routines = routines
        self.currentRoutineID = currentRoutineID
        self.onAssign = onAssign
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onAssign(nil)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "moon.zzz.fill")
                                .foregroundStyle(GymTheme.label3)
                            Text("Rest Day")
                                .foregroundStyle(GymTheme.label)
                            Spacer()
                            if currentRoutineID == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(GymTheme.green)
                            }
                        }
                    }
                }

                Section("Available Routines") {
                    ForEach(routines) { routine in
                        Button {
                            onAssign(routine.id)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: routine.iconName)
                                    .font(.system(size: 18))
                                    .foregroundStyle(GymTheme.green)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(routine.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(GymTheme.label)
                                    Text("\(routine.exercises.count) exercises")
                                        .font(.caption)
                                        .foregroundStyle(GymTheme.label3)
                                }

                                Spacer()

                                if currentRoutineID == routine.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(GymTheme.green)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Schedule for \(weekdayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
