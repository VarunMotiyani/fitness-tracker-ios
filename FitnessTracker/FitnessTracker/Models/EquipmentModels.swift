import Foundation
import FitnessDomain
import ExerciseCatalog

public struct EquipmentProfile: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var availableEquipmentRaws: [String]

    public init(id: String = UUID().uuidString, name: String, availableEquipmentRaws: [String] = []) {
        self.id = id
        self.name = name
        self.availableEquipmentRaws = availableEquipmentRaws
    }

    public static let defaults: [EquipmentProfile] = [
        EquipmentProfile(
            id: "commercial_gym",
            name: "Commercial Gym",
            availableEquipmentRaws: Equipment.allCases.map(\.rawValue)
        ),
        EquipmentProfile(
            id: "home_dumbbells",
            name: "Home (Dumbbells & Bodyweight)",
            availableEquipmentRaws: [Equipment.dumbbell.rawValue, Equipment.bodyweight.rawValue, Equipment.bands.rawValue]
        ),
        EquipmentProfile(
            id: "travel_hotel",
            name: "Travel / Hotel",
            availableEquipmentRaws: [Equipment.bodyweight.rawValue, Equipment.dumbbell.rawValue]
        )
    ]
}

/// Equipment-availability filter (parity with openGym's `equipment.js` `exAvailable`):
/// purely additive — filtering off, or no matching profile, shows everything. Bodyweight
/// is never gated, since no gym-or-home setup can take it away from you.
public enum EquipmentFilter {
    /// Whether `exercise` can be performed under the profile named by `activeID` inside
    /// `profilesJSON`. Reads straight from the persisted `@AppStorage` values so every call
    /// site (library, pickers, swap sheet) shares one source of truth without needing a
    /// shared observable object.
    public static func isAvailable(
        _ exercise: Exercise,
        filterOn: Bool,
        activeID: String,
        profilesJSON: String
    ) -> Bool {
        guard filterOn else { return true }
        guard exercise.equipment != .bodyweight else { return true }
        guard let profile = activeProfile(activeID: activeID, profilesJSON: profilesJSON) else { return true }
        return profile.availableEquipmentRaws.contains(exercise.equipment.rawValue)
    }

    private static func activeProfile(activeID: String, profilesJSON: String) -> EquipmentProfile? {
        guard let data = profilesJSON.data(using: .utf8),
              let profiles = try? JSONDecoder().decode([EquipmentProfile].self, from: data),
              !profiles.isEmpty
        else {
            return EquipmentProfile.defaults.first(where: { $0.id == activeID })
        }
        return profiles.first(where: { $0.id == activeID })
    }
}
