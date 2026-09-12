import Foundation
import SwiftData
import FitnessDomain
import ExerciseCatalog

/// A user-authored exercise. The catalog remains immutable; these rows are
/// projected into the same `Exercise` value type wherever the library is used.
@Model
final class CustomExerciseModel {
    var id: UUID
    var name: String
    var primaryMuscleRaw: String
    var secondaryMuscleRaws: [String]
    var equipmentRaw: String
    var mechanicRaw: String
    var forceRaw: String?
    var difficultyRaw: String
    var isUnilateral: Bool
    var instructions: String
    var photoFilename: String?
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, primaryMuscle: MuscleGroup,
         equipment: Equipment, secondaryMuscles: [MuscleGroup] = [],
         mechanic: Mechanic = .compound, force: ForceType? = nil,
         difficulty: Difficulty = .intermediate, isUnilateral: Bool = false,
         instructions: String = "", photoFilename: String? = nil) {
        self.id = id
        self.name = name
        self.primaryMuscleRaw = primaryMuscle.rawValue
        self.secondaryMuscleRaws = secondaryMuscles.map(\.rawValue)
        self.equipmentRaw = equipment.rawValue
        self.mechanicRaw = mechanic.rawValue
        self.forceRaw = force?.rawValue
        self.difficultyRaw = difficulty.rawValue
        self.isUnilateral = isUnilateral
        self.instructions = instructions
        self.photoFilename = photoFilename
        self.createdAt = .now
        self.updatedAt = .now
    }

    @MainActor
    var asExercise: Exercise {
        Exercise(id: id.uuidString, name: name,
                 primaryMuscle: MuscleGroup(rawValue: primaryMuscleRaw) ?? .chest,
                 secondaryMuscles: secondaryMuscleRaws.compactMap(MuscleGroup.init(rawValue:)),
                 equipment: Equipment(rawValue: equipmentRaw) ?? .other,
                 mechanic: Mechanic(rawValue: mechanicRaw) ?? .unknown,
                 force: forceRaw.flatMap(ForceType.init(rawValue:)),
                 difficulty: Difficulty(rawValue: difficultyRaw) ?? .intermediate,
                 isUnilateral: isUnilateral,
                 instructions: instructions.split(separator: "\n").map(String.init),
                 imagePaths: CustomExercisePhotoStore.url(for: photoFilename).map { [$0.absoluteString] } ?? [])
    }
}

struct CustomExerciseDraft: Equatable {
    var name = ""
    var primaryMuscle: MuscleGroup?
    var secondaryMuscles: Set<MuscleGroup> = []
    var equipment: Equipment = .bodyweight
    var mechanic: Mechanic = .compound
    var force: ForceType? = nil
    var difficulty: Difficulty = .intermediate
    var isUnilateral = false
    var instructions = ""
    var photoFilename: String?

    init() {}

    var validationError: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter an exercise name." }
        guard primaryMuscle != nil else { return "Choose the main muscle group." }
        return nil
    }

    func makeModel(existing: CustomExerciseModel? = nil) -> CustomExerciseModel {
        let model = existing ?? CustomExerciseModel(name: name, primaryMuscle: primaryMuscle ?? .chest, equipment: equipment)
        model.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        model.primaryMuscleRaw = (primaryMuscle ?? .chest).rawValue
        model.secondaryMuscleRaws = secondaryMuscles.sorted { $0.rawValue < $1.rawValue }.map(\.rawValue)
        model.equipmentRaw = equipment.rawValue
        model.mechanicRaw = mechanic.rawValue
        model.forceRaw = force?.rawValue
        model.difficultyRaw = difficulty.rawValue
        model.isUnilateral = isUnilateral
        model.instructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        model.photoFilename = photoFilename
        model.updatedAt = .now
        return model
    }

    init(model: CustomExerciseModel) {
        name = model.name
        primaryMuscle = MuscleGroup(rawValue: model.primaryMuscleRaw)
        secondaryMuscles = Set(model.secondaryMuscleRaws.compactMap(MuscleGroup.init(rawValue:)))
        equipment = Equipment(rawValue: model.equipmentRaw) ?? .bodyweight
        mechanic = Mechanic(rawValue: model.mechanicRaw) ?? .compound
        force = model.forceRaw.flatMap(ForceType.init(rawValue:))
        difficulty = Difficulty(rawValue: model.difficultyRaw) ?? .intermediate
        isUnilateral = model.isUnilateral
        instructions = model.instructions
        photoFilename = model.photoFilename
    }
}
