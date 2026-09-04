import FitnessDomain
import ExerciseCatalog

/// Effective-set muscle-balance model (parity with openGym's `muscles.js`): a compound
/// lift doesn't count as "one full set" for every muscle it touches — the primary mover
/// gets full credit and each secondary muscle gets partial credit, so a balance chart
/// build from many compounds doesn't read as if every muscle were trained equally hard.
public enum MuscleBalanceModel {
    /// Fractional credit a secondary (non-primary) muscle gets per working set, relative
    /// to the primary mover's full credit of `1.0`.
    public static let secondaryCreditFraction = 0.5

    /// The muscle-map slugs the Stats screen surfaces: the 13 canonical `MuscleGroup`
    /// slugs plus a few finer body-map regions that have no dedicated `MuscleGroup` case
    /// but still appear on the interactive body map (hip flexors, shins/tibialis, etc.).
    public static let allSlugs: [String] = [
        "chest", "abs", "biceps", "triceps", "deltoids", "trapezius", "forearm",
        "quadriceps", "calves", "upper-back", "lower-back", "gluteal", "hamstring",
        "obliques", "hip-flexors", "tibialis"
    ]

    /// Maps a catalog `MuscleGroup` onto its canonical body-map slug.
    public static func canonicalSlug(for muscle: MuscleGroup) -> String {
        switch muscle {
        case .chest: return "chest"
        case .abs: return "abs"
        case .biceps: return "biceps"
        case .triceps: return "triceps"
        case .shoulders: return "deltoids"
        case .traps: return "trapezius"
        case .forearms: return "forearm"
        case .quads: return "quadriceps"
        case .calves: return "calves"
        case .back: return "upper-back"
        case .lowerBack: return "lower-back"
        case .glutes: return "gluteal"
        case .hamstrings: return "hamstring"
        }
    }

    /// Human-readable label for a slug, including the body-map-only slugs that have no
    /// `MuscleGroup` case of their own.
    public static func displayName(for slug: String) -> String {
        let names: [String: String] = [
            "chest": "Chest", "abs": "Abs", "biceps": "Biceps", "triceps": "Triceps",
            "deltoids": "Shoulders", "trapezius": "Traps", "forearm": "Forearms",
            "quadriceps": "Quads", "calves": "Calves", "upper-back": "Upper back",
            "lower-back": "Lower back", "gluteal": "Glutes", "hamstring": "Hamstrings",
            "obliques": "Obliques", "adductors": "Adductors", "serratus": "Serratus",
            "hip-flexors": "Hip flexors", "tibialis": "Shins"
        ]
        return names[slug] ?? slug.capitalized
    }

    /// One exercise's contribution to a muscle-balance window: how many working sets of
    /// it were logged (warm-ups and skipped entries already excluded by the caller).
    public struct EffectiveSetItem: Sendable {
        public let exercise: Exercise
        public let sets: Int

        public init(exercise: Exercise, sets: Int) {
            self.exercise = exercise
            self.sets = sets
        }
    }

    /// Effective-set volume per muscle slug: the primary muscle gets full credit per
    /// working set, each secondary muscle gets `secondaryCreditFraction` credit — a
    /// compound trains more than one muscle, but not each of them "one full set" worth.
    public static func loadOf(items: [EffectiveSetItem]) -> [String: Double] {
        var load: [String: Double] = [:]
        for item in items {
            guard item.sets > 0 else { continue }
            let primarySlug = canonicalSlug(for: item.exercise.primaryMuscle)
            load[primarySlug, default: 0] += Double(item.sets)
            for secondary in item.exercise.secondaryMuscles {
                let slug = canonicalSlug(for: secondary)
                load[slug, default: 0] += Double(item.sets) * secondaryCreditFraction
            }
        }
        return load
    }

    /// Slugs with recorded load, heaviest first, and the complement: known slugs with no
    /// (or zero) load in this window — the "not trained" list.
    public static func rankOf(load: [String: Double]) -> (worked: [String], missed: [String]) {
        let worked = load
            .filter { $0.value > 0 }
            .keys
            .sorted { (load[$0] ?? 0) > (load[$1] ?? 0) }
        let missed = allSlugs.filter { (load[$0] ?? 0) <= 0 }
        return (worked, missed)
    }

    /// Continuous load bucketed into 5 discrete shading levels (0...4) for the body-map
    /// SVG, relative to the busiest muscle in the window.
    public static func levelsOf(load: [String: Double]) -> [String: Int] {
        let maxLoad = max(1.0, load.values.max() ?? 1.0)
        var levels: [String: Int] = [:]
        for (slug, value) in load {
            let ratio = value / maxLoad
            if ratio >= 0.75 { levels[slug] = 4 }
            else if ratio >= 0.50 { levels[slug] = 3 }
            else if ratio >= 0.25 { levels[slug] = 2 }
            else if ratio > 0 { levels[slug] = 1 }
            else { levels[slug] = 0 }
        }
        return levels
    }
}
