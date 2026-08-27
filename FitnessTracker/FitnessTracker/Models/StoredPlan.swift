import Foundation
import SwiftData
import FitnessDomain

/// A generated weekly plan, persisted as a Codable blob. The plan tree itself
/// (`WeeklyPlan` and children) is not modelled in SwiftData — 1b only ever reads
/// it back whole for the read-only plan view.
@Model
final class StoredPlan {
    var generatedAt: Date
    var weekStartDate: Date
    var planJSON: Data
    var hadValidationIssues: Bool

    init(plan: WeeklyPlan, hadValidationIssues: Bool) throws {
        self.generatedAt = .now
        self.weekStartDate = plan.weekStartDate
        self.planJSON = try JSONEncoder().encode(plan)
        self.hadValidationIssues = hadValidationIssues
    }

    func decodedPlan() throws -> WeeklyPlan {
        try JSONDecoder().decode(WeeklyPlan.self, from: planJSON)
    }
}
