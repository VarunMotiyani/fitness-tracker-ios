import Foundation

public enum BarType: String, Sendable, Codable, Equatable, CaseIterable {
    case olympicBarbell      // 20 kg / 45 lb
    case womensBarbell       // 15 kg / 35 lb
    case ezBarbell           // 10 kg / 25 lb
    case smithMachine        // 9 kg / 20 lb
    case trapBar             // 25 kg / 55 lb
    
    public var defaultWeightKg: Double {
        switch self {
        case .olympicBarbell: return 20.0
        case .womensBarbell: return 15.0
        case .ezBarbell: return 10.0
        case .smithMachine: return 9.0
        case .trapBar: return 25.0
        }
    }
    
    public var defaultWeightLb: Double {
        switch self {
        case .olympicBarbell: return 45.0
        case .womensBarbell: return 35.0
        case .ezBarbell: return 25.0
        case .smithMachine: return 20.0
        case .trapBar: return 55.0
        }
    }
    
    public var displayName: String {
        switch self {
        case .olympicBarbell: return "Olympic Barbell (20 kg / 45 lb)"
        case .womensBarbell: return "Women's Olympic Bar (15 kg / 35 lb)"
        case .ezBarbell: return "EZ Bar (10 kg / 25 lb)"
        case .smithMachine: return "Smith Machine (9 kg / 20 lb)"
        case .trapBar: return "Trap / Hex Bar (25 kg / 55 lb)"
        }
    }
}

public struct PlateLoadingResult: Sendable, Codable, Equatable {
    public let totalWeight: Double
    public let barWeight: Double
    public let perSideWeight: Double
    public let platesPerSide: [Double]
    public let unitString: String
    
    public init(totalWeight: Double, barWeight: Double, perSideWeight: Double, platesPerSide: [Double], unitString: String = "kg") {
        self.totalWeight = totalWeight
        self.barWeight = barWeight
        self.perSideWeight = perSideWeight
        self.platesPerSide = platesPerSide
        self.unitString = unitString
    }
    
    public var summary: String {
        guard perSideWeight > 0 else {
            return "Bar \(formatted(barWeight)) \(unitString)"
        }
        if platesPerSide.isEmpty {
            return "Bar \(formatted(barWeight)) \(unitString) · \(formatted(perSideWeight)) \(unitString) / side"
        }
        let plateList = platesPerSide.map { "\(formatted($0))" }.joined(separator: ", ")
        return "Bar \(formatted(barWeight)) \(unitString) · \(formatted(perSideWeight)) \(unitString) / side [\(plateList)]"
    }
    
    private func formatted(_ val: Double) -> String {
        if val.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", val)
        } else {
            return String(format: "%.1f", val)
        }
    }
}

public enum PlateMath {
    public static let standardKgPlates: [Double] = [25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25]
    public static let standardLbPlates: [Double] = [45.0, 35.0, 25.0, 10.0, 5.0, 2.5]
    
    /// Calculate plate loading per side given total target load and bar weight.
    public static func calculate(
        totalWeight: Double,
        barWeight: Double = BarType.olympicBarbell.defaultWeightKg,
        availablePlates: [Double] = standardKgPlates,
        unitString: String = "kg"
    ) -> PlateLoadingResult {
        guard totalWeight > barWeight, barWeight >= 0 else {
            return PlateLoadingResult(
                totalWeight: max(0, totalWeight),
                barWeight: barWeight,
                perSideWeight: 0,
                platesPerSide: [],
                unitString: unitString
            )
        }
        
        let perSide = (totalWeight - barWeight) / 2.0
        var remaining = perSide
        var plates: [Double] = []
        
        let sortedPlates = availablePlates.filter { $0 > 0 }.sorted(by: >)
        
        for plate in sortedPlates {
            while remaining >= plate - 0.001 {
                plates.append(plate)
                remaining -= plate
            }
        }
        
        return PlateLoadingResult(
            totalWeight: totalWeight,
            barWeight: barWeight,
            perSideWeight: (perSide * 100).rounded() / 100,
            platesPerSide: plates,
            unitString: unitString
        )
    }
}
