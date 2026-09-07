import SwiftUI
import FitnessDomain
import Metrics
import RuleEngine

struct BackfillEntryView: View {
    @Environment(\.dismiss) private var dismiss
    let plan: WeeklyPlan
    let onStartBackfill: (PlannedSession, Date, Int, UUID?) -> Void

    @State private var selectedSessionIndex: Int = 0
    @State private var workoutDate: Date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    @State private var durationMinutes: Int = 60
    @State private var replaceSessionID: UUID? = nil

    init(
        plan: WeeklyPlan,
        onStartBackfill: @escaping (PlannedSession, Date, Int, UUID?) -> Void
    ) {
        self.plan = plan
        self.onStartBackfill = onStartBackfill
    }

    private var sessionsList: [(index: Int, focus: String)] {
        plan.sessions.enumerated().map { (index: $0.offset, focus: $0.element.focusMuscles.map(\.rawValue).joined(separator: ", ")) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout Routine") {
                    Picker("Routine", selection: $selectedSessionIndex) {
                        ForEach(sessionsList, id: \.index) { item in
                            Text("Session \(item.index + 1) · \(item.focus.isEmpty ? "General" : item.focus)")
                                .tag(item.index)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("When was this workout?") {
                    DatePicker("Date & Time", selection: $workoutDate, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    
                    Stepper("Duration: \(durationMinutes) min", value: $durationMinutes, in: 5...300, step: 5)
                }

                Section {
                    Button {
                        guard let session = plan.sessions.indices.contains(selectedSessionIndex) ? plan.sessions[selectedSessionIndex] : plan.sessions.first else {
                            return
                        }
                        onStartBackfill(session, workoutDate, durationMinutes, replaceSessionID)
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Log Past Workout")
                                .font(.headline)
                                .foregroundStyle(GymTheme.bg)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .background(GymTheme.green, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle("Log Past Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
