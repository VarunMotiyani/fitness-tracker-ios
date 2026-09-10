import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import FitnessDomain

struct CustomExerciseEditorSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CustomExerciseDraft
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var errorMessage: String?

    let existing: CustomExerciseModel?
    let onSaved: () -> Void

    private var currentPhotoImage: UIImage? {
        if let photoData, let image = UIImage(data: photoData) { return image }
        if let url = CustomExercisePhotoStore.url(for: draft.photoFilename) {
            return UIImage(contentsOfFile: url.path)
        }
        return nil
    }

    init(existing: CustomExerciseModel? = nil, onSaved: @escaping () -> Void = {}) {
        self.existing = existing
        self.onSaved = onSaved
        _draft = State(initialValue: existing.map { CustomExerciseDraft(model: $0) } ?? CustomExerciseDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Exercise name", text: $draft.name)
                        .textInputAutocapitalization(.words)
                    if let error = draft.validationError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Basics")
                } footer: {
                    Text("Use the name you’ll recognize while logging a workout.")
                }

                Section("Target") {
                    Picker("Main muscle", selection: Binding(
                        get: { draft.primaryMuscle },
                        set: { draft.primaryMuscle = $0 })) {
                        Text("Choose a muscle").tag(MuscleGroup?.none)
                        ForEach(MuscleGroup.allCases, id: \.self) { muscle in
                            Text(muscle.label).tag(MuscleGroup?.some(muscle))
                        }
                    }
                    Picker("Equipment", selection: $draft.equipment) {
                        ForEach(Equipment.allCases, id: \.self) { equipment in
                            Text(equipment.label).tag(equipment)
                        }
                    }
                    Picker("Movement", selection: $draft.mechanic) {
                        Text("Compound").tag(Mechanic.compound)
                        Text("Isolation").tag(Mechanic.isolation)
                        Text("Static / hold").tag(Mechanic.unknown)
                    }
                    Picker("Force", selection: Binding(
                        get: { draft.force },
                        set: { draft.force = $0 })) {
                        Text("Not specified").tag(ForceType?.none)
                        Text("Push").tag(ForceType?.some(.push))
                        Text("Pull").tag(ForceType?.some(.pull))
                        Text("Static").tag(ForceType?.some(.static))
                    }
                    Picker("Difficulty", selection: $draft.difficulty) {
                        Text("Beginner").tag(Difficulty.beginner)
                        Text("Intermediate").tag(Difficulty.intermediate)
                        Text("Expert").tag(Difficulty.expert)
                    }
                    Toggle("Unilateral (one side at a time)", isOn: $draft.isUnilateral)
                }

                Section("Secondary muscles") {
                    ForEach(MuscleGroup.allCases, id: \.self) { muscle in
                        Toggle(muscle.label, isOn: Binding(
                            get: { draft.secondaryMuscles.contains(muscle) },
                            set: { isOn in
                                if isOn { draft.secondaryMuscles.insert(muscle) }
                                else { draft.secondaryMuscles.remove(muscle) }
                            }))
                    }
                }

                Section("Instructions") {
                    TextField("One step per line (optional)", text: $draft.instructions, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Photo") {
                    Group {
                        if let image = currentPhotoImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .frame(height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        } else {
                            Label("Optional demonstration photo", systemImage: "photo")
                                .frame(maxWidth: .infinity)
                                .frame(height: 88)
                                .foregroundStyle(.secondary)
                                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Choose or change exercise photo", systemImage: "photo.on.rectangle")
                    }
                    if photoData != nil || draft.photoFilename != nil {
                        Label("Photo saved on this iPhone", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Remove photo", role: .destructive) {
                            photoData = nil
                            draft.photoFilename = nil
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(GymTheme.bg.ignoresSafeArea())
            .navigationTitle(existing == nil ? "New exercise" : "Edit exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.bold)
                        .disabled(draft.validationError != nil)
                }
            }
            .task(id: selectedPhoto) {
                guard let selectedPhoto else { return }
                photoData = try? await selectedPhoto.loadTransferable(type: Data.self)
            }
            .alert("Couldn’t save exercise", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Try again.")
            }
        }
    }

    private func save() {
        guard draft.validationError == nil else { return }
        do {
            let previousPhotoFilename = existing?.photoFilename
            let model = draft.makeModel(existing: existing)
            if let photoData {
                model.photoFilename = try CustomExercisePhotoStore.save(photoData, id: model.id)
            }
            if previousPhotoFilename != model.photoFilename {
                CustomExercisePhotoStore.delete(filename: previousPhotoFilename)
            }
            if existing == nil { context.insert(model) }
            try context.save()
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
