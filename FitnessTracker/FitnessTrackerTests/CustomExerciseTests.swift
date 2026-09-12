import Testing
import SwiftData
import Foundation
import FitnessDomain
import ExerciseCatalog
@testable import FitnessTracker

@MainActor
struct CustomExerciseTests {
    @Test func draftValidationRequiresNameAndPrimaryMuscle() {
        var draft = CustomExerciseDraft()
        #expect(draft.validationError != nil)
        draft.name = "Cable Fly"
        #expect(draft.validationError != nil)
        draft.primaryMuscle = .chest
        #expect(draft.validationError == nil)
    }

    @Test func modelConvertsToCatalogExercise() throws {
        let model = CustomExerciseModel(name: "Cable Fly", primaryMuscle: .chest, equipment: .cable)
        model.instructions = "Set the cable handles at chest height.\nBring your hands together with control."
        let exercise = model.asExercise
        #expect(exercise.id == model.id.uuidString)
        #expect(exercise.name == "Cable Fly")
        #expect(exercise.primaryMuscle == .chest)
        #expect(exercise.instructions.count == 2)
        #expect(exercise.imagePaths.isEmpty)
    }

    @Test func customExerciseRoundTripsThroughSwiftData() throws {
        let container = try ModelContainer(for: CustomExerciseModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let model = CustomExerciseModel(name: "My Press", primaryMuscle: .shoulders, equipment: .dumbbell)
        context.insert(model)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<CustomExerciseModel>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "My Press")
    }
}
