import SwiftUI
import FitnessDomain

struct OnboardingView: View {
    /// Called once, with the populated (but not-yet-persisted) profile, when the
    /// user taps "Create my plan" on the review step.
    let onComplete: (UserProfile) -> Void

    @State private var model = OnboardingModel()
    @State private var stepIndex = 0

    private let stepCount = 7

    var body: some View {
        NavigationStack {
            currentStep
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if stepIndex > 0 {
                            Button("Back") { stepIndex -= 1 }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if stepIndex < stepCount - 1 {
                            Button("Next") { stepIndex += 1 }
                                .disabled(!canAdvance)
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var currentStep: some View {
        switch stepIndex {
        case 0: GoalStep(model: model)
        case 1: ExperienceStep(model: model)
        case 2: BodyStep(model: model)
        case 3: ScheduleStep(model: model)
        case 4: EquipmentStep(model: model)
        case 5: LimitationsStep(model: model)
        default:
            ReviewStep(model: model) {
                if let profile = model.makeProfile() { onComplete(profile) }
            }
        }
    }

    private var canAdvance: Bool {
        switch stepIndex {
        case 0: model.goal != nil
        case 1: model.experience != nil
        case 2: model.heightCm > 0 && model.weightKg > 0 && model.birthYear >= 1900
        case 3: (2...7).contains(model.sessionsPerWeek)
        case 4: !model.equipment.isEmpty
        default: true
        }
    }
}
