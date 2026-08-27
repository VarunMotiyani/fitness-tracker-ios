import FitnessDomain

public enum FreeExerciseDBMapper {

    public static func map(_ raw: RawFreeExerciseDBExercise) -> Exercise? {
        guard let firstPrimary = raw.primaryMuscles.first,
              let primary = muscle(firstPrimary) else {
            return nil
        }

        var seenSecondary: Set<MuscleGroup> = [primary]
        var secondaries: [MuscleGroup] = []
        for name in raw.secondaryMuscles {
            guard let m = muscle(name), !seenSecondary.contains(m) else { continue }
            seenSecondary.insert(m)
            secondaries.append(m)
        }

        return Exercise(
            id: raw.id ?? raw.name.replacingOccurrences(of: " ", with: "_"),
            name: raw.name,
            primaryMuscle: primary,
            secondaryMuscles: secondaries,
            equipment: equipment(raw.equipment),
            mechanic: mechanic(raw.mechanic),
            force: force(raw.force),
            difficulty: difficulty(raw.level),
            isUnilateral: isUnilateral(raw.name),
            instructions: raw.instructions,
            imagePaths: raw.images
        )
    }

    static func muscle(_ value: String) -> MuscleGroup? {
        switch value.lowercased() {
        case "chest": return .chest
        case "lats", "middle back": return .back
        case "lower back": return .lowerBack
        case "traps", "neck": return .traps
        case "shoulders": return .shoulders
        case "biceps": return .biceps
        case "triceps": return .triceps
        case "forearms": return .forearms
        case "quadriceps": return .quads
        case "hamstrings": return .hamstrings
        case "glutes", "abductors", "adductors": return .glutes
        case "calves": return .calves
        case "abdominals": return .abs
        default: return nil
        }
    }

    static func equipment(_ value: String?) -> Equipment {
        switch value?.lowercased() {
        case "barbell": return .barbell
        case "dumbbell": return .dumbbell
        case "cable": return .cable
        case "machine": return .machine
        case "body only": return .bodyweight
        case "kettlebells": return .kettlebell
        case "bands": return .bands
        case "e-z curl bar": return .ezBar
        default: return .other
        }
    }

    static func mechanic(_ value: String?) -> Mechanic {
        switch value?.lowercased() {
        case "compound": return .compound
        case "isolation": return .isolation
        default: return .unknown
        }
    }

    static func force(_ value: String?) -> ForceType? {
        switch value?.lowercased() {
        case "push": return .push
        case "pull": return .pull
        case "static": return .static
        default: return nil
        }
    }

    static func difficulty(_ value: String) -> Difficulty {
        switch value.lowercased() {
        case "beginner": return .beginner
        case "expert": return .expert
        default: return .intermediate
        }
    }

    static func isUnilateral(_ name: String) -> Bool {
        let n = name.lowercased()
        let markers = ["single-arm", "single arm", "one-arm", "one arm",
                       "single-leg", "single leg", "one-leg", "one leg",
                       "alternating", "alternate"]
        return markers.contains { n.contains($0) }
    }
}
