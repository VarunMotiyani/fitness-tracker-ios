import FitnessDomain

extension Goal {
    var label: String {
        switch self {
        case .loseFat:         "Lose fat"
        case .buildMuscle:     "Build muscle"
        case .getStronger:     "Get stronger"
        case .generalFitness:  "General fitness"
        }
    }
}

extension ExperienceLevel {
    var label: String {
        switch self {
        case .beginner:      "New to the gym"
        case .intermediate:  "About 6 months – 2 years"
        case .advanced:      "2+ years training"
        }
    }
}

extension Equipment {
    var label: String {
        switch self {
        case .barbell:     "Barbell"
        case .dumbbell:    "Dumbbells"
        case .cable:       "Cable machine"
        case .machine:     "Plate / selectorized machines"
        case .bodyweight:  "Bodyweight only"
        case .kettlebell:  "Kettlebells"
        case .bands:       "Resistance bands"
        case .ezBar:       "EZ curl bar"
        case .smithMachine:    "Smith machine"
        case .leverageMachine: "Leverage machine"
        case .stabilityBall:   "Stability ball"
        case .medicineBall:    "Medicine ball"
        case .sled:            "Sled"
        case .rope:            "Rope"
        case .roller:          "Foam roller"
        case .cardioMachine:   "Cardio machine"
        case .other:       "Other"
        }
    }
}

extension MuscleGroup {
    var label: String {
        switch self {
        case .chest:       "Chest"
        case .back:        "Back"
        case .lowerBack:   "Lower back"
        case .traps:       "Traps"
        case .shoulders:   "Shoulders"
        case .biceps:      "Biceps"
        case .triceps:     "Triceps"
        case .forearms:    "Forearms"
        case .quads:       "Quads"
        case .hamstrings:  "Hamstrings"
        case .glutes:      "Glutes"
        case .calves:      "Calves"
        case .abs:         "Abs"
        }
    }
}
