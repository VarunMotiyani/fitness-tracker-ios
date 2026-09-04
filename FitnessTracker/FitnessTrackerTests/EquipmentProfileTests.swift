import Testing
import Foundation
import FitnessDomain
@testable import FitnessTracker

@MainActor
@Suite struct EquipmentProfileTests {

    @Test func defaultProfilesExist() {
        let defaults = EquipmentProfile.defaults
        #expect(defaults.count == 3)
        #expect(defaults.contains(where: { $0.id == "commercial_gym" }))
        #expect(defaults.contains(where: { $0.id == "home_dumbbells" }))
        #expect(defaults.contains(where: { $0.id == "travel_hotel" }))
    }

    @Test func presetEquipmentValues() {
        let gym = EquipmentProfile.defaults.first(where: { $0.id == "commercial_gym" })!
        #expect(gym.availableEquipmentRaws.contains(Equipment.barbell.rawValue))
        #expect(gym.availableEquipmentRaws.contains(Equipment.cable.rawValue))
        #expect(gym.availableEquipmentRaws.contains(Equipment.machine.rawValue))

        let hotel = EquipmentProfile.defaults.first(where: { $0.id == "travel_hotel" })!
        #expect(hotel.availableEquipmentRaws.contains(Equipment.bodyweight.rawValue))
        #expect(hotel.availableEquipmentRaws.contains(Equipment.dumbbell.rawValue))
        #expect(!hotel.availableEquipmentRaws.contains(Equipment.barbell.rawValue))
    }

    @Test func encodingAndDecoding() throws {
        let profile = EquipmentProfile(
            id: "my_garage",
            name: "Garage Gym",
            availableEquipmentRaws: ["barbell", "dumbbell", "bands"]
        )
        let data = try JSONEncoder().encode([profile])
        let decoded = try JSONDecoder().decode([EquipmentProfile].self, from: data)
        #expect(decoded.count == 1)
        #expect(decoded[0].id == "my_garage")
        #expect(decoded[0].name == "Garage Gym")
        #expect(decoded[0].availableEquipmentRaws == ["barbell", "dumbbell", "bands"])
    }
}
