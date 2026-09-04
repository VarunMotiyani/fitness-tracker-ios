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

    public static func muscle(_ value: String) -> MuscleGroup? {
        let v = value.lowercased()
        switch v {
        case "chest", "pectorals":
            return .chest
        case "lats", "middle back", "back", "upper back":
            return .back
        case "lower back", "spine":
            return .lowerBack
        case "traps", "neck", "trapezius", "levator scapulae":
            return .traps
        case "shoulders", "delts", "rear deltoids", "anterior deltoids", "lateral deltoids":
            return .shoulders
        case "biceps", "brachialis":
            return .biceps
        case "triceps":
            return .triceps
        case "forearms", "wrist flexors", "wrist extensors":
            return .forearms
        case "quadriceps", "quads":
            return .quads
        case "hamstrings":
            return .hamstrings
        case "glutes", "abductors", "adductors", "hip flexors", "piriformis":
            return .glutes
        case "calves", "soleus", "gastrocnemius", "ankle stabilizers":
            return .calves
        case "abdominals", "abs", "waist", "core", "obliques":
            return .abs
        case "cardiovascular system", "cardio":
            return .quads
        default:
            return nil
        }
    }

    /// Maps a raw equipment string from either bundled catalog (Gym Visual's 28-value
    /// vocabulary or free-exercise-db's 12-value one) onto `Equipment`. "weighted" (a
    /// bodyweight movement done with added load, e.g. a weighted pull-up) maps to
    /// `.bodyweight` — the base movement, and what an equipment-availability check
    /// actually cares about, is bodyweight.
    public static func equipment(_ value: String?) -> Equipment {
        guard let v = value?.lowercased() else { return .other }
        switch v {
        case "barbell", "olympic barbell", "trap bar":
            return .barbell
        case "dumbbell":
            return .dumbbell
        case "cable":
            return .cable
        case "machine":
            return .machine
        case "smith machine":
            return .smithMachine
        case "leverage machine":
            return .leverageMachine
        case "sled machine", "sled":
            return .sled
        case "body only", "body weight", "assisted", "suspension", "weighted":
            return .bodyweight
        case "kettlebells", "kettlebell":
            return .kettlebell
        case "bands", "band", "resistance band":
            return .bands
        case "e-z curl bar", "ez barbell":
            return .ezBar
        case "stability ball", "exercise ball", "bosu ball":
            return .stabilityBall
        case "medicine ball":
            return .medicineBall
        case "rope":
            return .rope
        case "roller", "wheel roller", "foam roll":
            return .roller
        case "upper body ergometer", "skierg machine", "stationary bike",
             "elliptical machine", "stepmill machine":
            return .cardioMachine
        default:
            return .other
        }
    }

    public static func mechanic(_ value: String?) -> Mechanic {
        switch value?.lowercased() {
        case "compound": return .compound
        case "isolation": return .isolation
        default: return .unknown
        }
    }

    public static func force(_ value: String?) -> ForceType? {
        switch value?.lowercased() {
        case "push": return .push
        case "pull": return .pull
        case "static": return .static
        default: return nil
        }
    }

    public static func difficulty(_ value: String) -> Difficulty {
        switch value.lowercased() {
        case "beginner": return .beginner
        case "expert": return .expert
        default: return .intermediate
        }
    }

    public static func isUnilateral(_ name: String) -> Bool {
        let n = name.lowercased()
        let markers = ["single-arm", "single arm", "one-arm", "one arm",
                       "single-leg", "single leg", "one-leg", "one leg",
                       "alternating", "alternate"]
        return markers.contains { n.contains($0) }
    }
}
