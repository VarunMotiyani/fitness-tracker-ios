import Foundation
import FitnessDomain

public enum CatalogError: Error, Sendable, Equatable {
    case empty
}

public struct CatalogStore: Sendable {
    public let all: [Exercise]
    private let byID: [String: Exercise]

    public init(exercises: [Exercise]) {
        var ordered: [Exercise] = []
        var index: [String: Exercise] = [:]
        for exercise in exercises where index[exercise.id] == nil {
            index[exercise.id] = exercise
            ordered.append(exercise)
        }
        self.all = ordered
        self.byID = index
    }

    public static func load(fromJSONData data: Data) throws -> CatalogStore {
        let raw = try JSONDecoder().decode([RawFreeExerciseDBExercise].self, from: data)
        let mapped = raw.compactMap(FreeExerciseDBMapper.map)
        guard !mapped.isEmpty else { throw CatalogError.empty }
        return CatalogStore(exercises: mapped)
    }

    public func exercise(id: String) -> Exercise? { byID[id] }

    public func contains(id: String) -> Bool { byID[id] != nil }

    public func exercises(primaryMuscle: MuscleGroup,
                          availableEquipment: Set<Equipment>) -> [Exercise] {
        all.filter { $0.primaryMuscle == primaryMuscle && availableEquipment.contains($0.equipment) }
           .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }
}
