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

    init(generatedAt: Date, weekStartDate: Date, planJSON: Data, hadValidationIssues: Bool) {
        self.generatedAt = generatedAt
        self.weekStartDate = weekStartDate
        self.planJSON = planJSON
        self.hadValidationIssues = hadValidationIssues
    }

    // Non-persisted memo. `RootView` decodes the newest plan twice per body
    // pass (bar + content) and body re-runs on every tab/state change; the full
    // `WeeklyPlan` tree decode was a per-frame cost on-device. Keyed by the
    // blob itself so a regenerated plan busts it.
    @Transient private var cachedPlan: WeeklyPlan? = nil
    @Transient private var cachedFrom: Data? = nil

    func decodedPlan() throws -> WeeklyPlan {
        if let cachedPlan, cachedFrom == planJSON { return cachedPlan }
        let plan = try JSONDecoder().decode(WeeklyPlan.self, from: planJSON)
        cachedPlan = plan
        cachedFrom = planJSON
        return plan
    }
}
