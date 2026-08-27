import Foundation
import ExerciseCatalog

nonisolated enum BundledCatalogError: Error, Equatable {
    case resourceMissing
}

/// Loads the app-bundled exercise catalog (`catalog.json`, free-exercise-db raw shape)
/// into a `FitnessCore` `CatalogStore`.
///
/// `nonisolated` because this target defaults to `@MainActor` isolation (Xcode 26
/// "Default Actor Isolation = MainActor"), but catalog loading is pure and must be
/// callable from any context, including nonisolated tests.
nonisolated enum BundledCatalog {
    static func load(bundle: Bundle = .main,
                     resourceName: String = "catalog") throws -> CatalogStore {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw BundledCatalogError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        return try CatalogStore.load(fromJSONData: data)
    }
}
