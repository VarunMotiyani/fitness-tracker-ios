import SwiftUI
import FitnessDomain
import RuleEngine
import ExerciseCatalog

public struct ExerciseConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let exerciseName: String
    @Binding public var config: ExerciseConfig
    public let onSave: (ExerciseConfig) -> Void

    @State private var draft: ExerciseConfig
    @State private var useRepRange: Bool

    public init(
        exerciseName: String,
        config: Binding<ExerciseConfig>,
        onSave: @escaping (ExerciseConfig) -> Void
    ) {
        self.exerciseName = exerciseName
        self._config = config
        self.onSave = onSave
        self._draft = State(initialValue: config.wrappedValue)
        self._useRepRange = State(initialValue: config.wrappedValue.isRepRange)
    }

    private var minRepsBinding: Binding<Int> {
        Binding(
            get: { draft.repsMin ?? 8 },
            set: { draft.repsMin = min($0, (draft.repsMax ?? 12) - 1) }
        )
    }

    private var maxRepsBinding: Binding<Int> {
        Binding(
            get: { draft.repsMax ?? 12 },
            set: { draft.repsMax = max($0, (draft.repsMin ?? 8) + 1) }
        )
    }

    private var restSecBinding: Binding<Int> {
        Binding(
            get: { draft.restSec ?? 90 },
            set: { draft.restSec = $0 }
        )
    }

    private var cardioMinutesBinding: Binding<Int> {
        Binding(
            get: { max(1, draft.sec / 60) },
            set: { draft.sec = $0 * 60 }
        )
    }

    public var body: some View {
        NavigationStack {
            Form {
                modeSection
                detailsSection
                coachNoteSection
            }
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAction()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var modeSection: some View {
        Section("Logging Mode") {
            Picker("Mode", selection: $draft.mode) {
                Text("Reps").tag("reps")
                Text("Time").tag("time")
                Text("Cardio").tag("cardio")
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var detailsSection: some View {
        if draft.mode == "reps" {
            Section("Sets & Reps") {
                Stepper("Sets: \(draft.sets)", value: $draft.sets, in: 1...20)

                Toggle("Use a rep range", isOn: $useRepRange)
                    .tint(GymTheme.green)
                    .onChange(of: useRepRange) { _, newValue in
                        if newValue {
                            if draft.repsMin == nil { draft.repsMin = max(1, draft.reps - 2) }
                            if draft.repsMax == nil { draft.repsMax = draft.reps + 2 }
                        } else {
                            draft.repsMin = nil
                            draft.repsMax = nil
                        }
                    }

                if useRepRange {
                    let minVal = draft.repsMin ?? 8
                    let maxVal = draft.repsMax ?? 12
                    Stepper("Min reps: \(minVal)", value: minRepsBinding, in: 1...99)
                    Stepper("Max reps: \(maxVal)", value: maxRepsBinding, in: 2...100)
                } else {
                    Stepper("Target reps: \(draft.reps)", value: $draft.reps, in: 1...100)
                }

                if !draft.bodyweight {
                    HStack {
                        Text("Working Weight")
                        Spacer()
                        TextField("0.0", value: $draft.weightKg, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kg")
                            .foregroundStyle(GymTheme.label3)
                    }
                }

                HStack {
                    Text("Rest Timer")
                    Spacer()
                    if let rest = draft.restSec, rest > 0 {
                        Text("\(rest)s")
                            .foregroundStyle(GymTheme.green)
                    } else {
                        Text("Off")
                            .foregroundStyle(GymTheme.label3)
                    }
                }
                Stepper("", value: restSecBinding, in: 0...600, step: 15)
                    .labelsHidden()
            }

            Section("Exercise Options") {
                Toggle("Bodyweight (no external load)", isOn: $draft.bodyweight)
                    .tint(GymTheme.green)

                Toggle("Reps per side", isOn: $draft.perSide)
                    .tint(GymTheme.green)
            }
        } else if draft.mode == "time" {
            Section("Time Hold") {
                Stepper("Sets: \(draft.sets)", value: $draft.sets, in: 1...20)
                Stepper("Target Hold: \(draft.sec)s", value: $draft.sec, in: 5...600, step: 5)
                HStack {
                    Text("Added Weight")
                    Spacer()
                    TextField("0.0", value: $draft.weightKg, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("kg")
                }
            }
        } else {
            Section("Cardio") {
                Stepper("Duration: \(draft.sec / 60) min", value: cardioMinutesBinding, in: 1...180)
            }
        }
    }

    @ViewBuilder
    private var coachNoteSection: some View {
        Section("Plan Instruction / Coach Note") {
            TextField("E.g. Pause 2s at bottom, emphasize stretch", text: $draft.coachNote)
        }
    }

    private func saveAction() {
        if useRepRange, let rMin = draft.repsMin, let rMax = draft.repsMax {
        }
        config = draft
        onSave(draft)
        dismiss()
    }
}
