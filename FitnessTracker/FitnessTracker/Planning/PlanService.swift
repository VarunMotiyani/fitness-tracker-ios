import Foundation
import FitnessDomain
import ExerciseCatalog
import RuleEngine
import PlanValidation

nonisolated struct PlanResult {
    let plan: WeeklyPlan
    let issues: [ValidationIssue]
}

/// Turns a planning `UserContext` into a validated rule-engine `WeeklyPlan`.
///
/// `nonisolated` — pure computation over `FitnessCore` value types. Callers on the
/// main actor convert their `UserProfile` `@Model` with `makeUserContext()` first,
/// then hand the plain value here.
nonisolated struct PlanService {
    let catalog: CatalogStore

    init(catalog: CatalogStore) {
        self.catalog = catalog
    }

    /// Builds a `PlanService` from the app-bundled stub catalog.
    static func live() throws -> PlanService {
        PlanService(catalog: try BundledCatalog.load())
    }

    func generate(context: UserContext, weekStartDate: Date = .now) -> PlanResult {
        let plan = RulePlanBuilder(catalog: catalog).build(context: context, weekStartDate: weekStartDate)
        let issues = PlanValidator(catalog: catalog).validate(plan, context: context)
        return PlanResult(plan: plan, issues: issues)
    }
}
