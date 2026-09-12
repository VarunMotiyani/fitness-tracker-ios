import Foundation
import ExerciseCatalog

/// Holds the bundled `CatalogStore` merged with the user's custom exercises,
/// rebuilding only when either side actually changes.
///
/// `RootView.effectiveCatalog` is read from `content`, which SwiftUI
/// re-evaluates on every `body` pass (tab taps, `@Query` updates, `@AppStorage`
/// changes…). Rebuilding the ~1.5 MB catalog each time — a full copy of every
/// `Exercise` struct plus a dictionary build — was stalling the main thread on
/// every tab switch.
@MainActor
final class MergedCatalogCache {
    private var key: Int?
    private var cached: CatalogStore?

    func catalog(base: CatalogStore, custom: [CustomExerciseModel]) -> CatalogStore {
        var hasher = Hasher()
        // Identify the base catalog cheaply: count + endpoint ids distinguish
        // the bundled "gym visual" catalog from the free-exercise-db one
        // without hashing every entry. Neither is mutated after load.
        hasher.combine(base.all.count)
        hasher.combine(base.all.first?.id)
        hasher.combine(base.all.last?.id)
        hasher.combine(custom.count)
        for exercise in custom {
            hasher.combine(exercise.id)
            hasher.combine(exercise.updatedAt)
        }
        let newKey = hasher.finalize()
        if newKey == key, let cached { return cached }

        let merged = custom.isEmpty
            ? base
            : CatalogStore(exercises: base.all + custom.map { $0.asExercise })
        cached = merged
        key = newKey
        return merged
    }
}
