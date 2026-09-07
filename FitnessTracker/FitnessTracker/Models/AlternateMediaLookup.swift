import Foundation
import ExerciseCatalog

/// Finds a same-named exercise in the free-exercise-db catalog for a Gym Visual exercise,
/// so the workout runner can offer "use the free photo instead" per exercise without
/// touching exercise identity anywhere — plans, sessions, and history all keep resolving
/// against the Gym Visual catalog's IDs; this only ever supplies an alternate image list.
///
/// Coverage is partial by design: the two catalogs only share ~10% of their exercise names
/// (1,324 Gym Visual vs. 876 free-exercise-db, built independently), so most exercises
/// will have no alternate — `imagePaths(forExerciseNamed:)` returns `nil` for those, and
/// callers should simply not offer the toggle when it does.
enum AlternateMediaLookup {
    /// Lazily loaded once per process — the free-exercise-db catalog is ~1MB, no reason
    /// to decode it until something actually asks for an alternate.
    private static let byName: [String: [String]] = {
        guard let store = try? BundledCatalog.load(resourceName: "free_exercise_db") else { return [:] }
        var map: [String: [String]] = [:]
        for exercise in store.all where !exercise.imagePaths.isEmpty {
            map[normalize(exercise.name)] = exercise.imagePaths
        }
        return map
    }()

    private static func normalize(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The free-exercise-db (public-domain) image paths for an exercise with this name,
    /// if that exact name also exists in that dataset.
    static func imagePaths(forExerciseNamed name: String) -> [String]? {
        byName[normalize(name)]
    }
}
