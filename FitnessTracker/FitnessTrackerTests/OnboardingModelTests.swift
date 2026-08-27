import Testing
import FitnessDomain
@testable import FitnessTracker

@MainActor
struct OnboardingModelTests {

    @Test func incompleteUntilRequiredFieldsSet() {
        let m = OnboardingModel()
        #expect(m.isComplete == false)
        #expect(m.makeProfile() == nil)

        m.goal = .buildMuscle
        m.experience = .intermediate
        m.heightCm = 178
        m.weightKg = 76
        m.birthYear = 2001
        m.equipment = [.barbell, .dumbbell]
        #expect(m.isComplete == true)
    }

    @Test func makeProfileCarriesRawValues() throws {
        let m = OnboardingModel()
        m.goal = .loseFat
        m.experience = .beginner
        m.heightCm = 170; m.weightKg = 82; m.birthYear = 1999
        m.equipment = [.machine, .cable]
        m.excludedMuscles = [.lowerBack]

        let p = try #require(m.makeProfile())
        #expect(p.goalRaw == "loseFat")
        #expect(p.experienceRaw == "beginner")
        #expect(Set(p.availableEquipmentRaws) == ["machine", "cable"])
        #expect(p.excludedMuscleRaws == ["lowerBack"])
    }
}
