# FitnessTracker (app)

iOS app shell — **Phase 1b**. SwiftUI + SwiftData, iOS 26. Depends on the local
[`FitnessCore`](../FitnessCore) package for all training logic.

## What it does (1b)

Onboarding → rule-engine weekly plan → read-only plan view. Fully offline, no AI.

- **Onboarding** (7 steps): goal, experience, body stats, schedule, equipment
  checklist, areas to avoid, review.
- On "Create my plan": the answers become a `FitnessCore.UserContext`,
  `RulePlanBuilder` builds a plan, `PlanValidator` checks it, the plan is
  persisted as a Codable blob.
- **Plan view**: sessions, exercises (names from the bundled catalog), sets ×
  reps, rest, coach notes, weekly volume targets, and the "why this plan"
  rationale.
- **Settings** scaffold: profile summary, regenerate plan, start over, and a
  disabled "AI Coach — Phase 1c" row.

## Structure

| Path | Responsibility |
|------|----------------|
| `Models/UserProfile.swift` (+ `UserProfile+Mapping.swift`) | SwiftData `@Model` for the onboarding answers; `makeUserContext()` maps it to `FitnessCore` |
| `Models/StoredPlan.swift` | SwiftData `@Model` holding a `WeeklyPlan` as JSON |
| `Catalog/catalog.json` + `BundledCatalog.swift` | bundled **stub** catalog (20 exercises, free-exercise-db raw shape) → `CatalogStore` |
| `Planning/PlanService.swift` | `UserContext` → `RulePlanBuilder` → `PlanValidator` → `PlanResult` (`nonisolated`) |
| `Features/Onboarding/` | the 7-step SwiftUI flow + `OnboardingModel` draft state |
| `Features/Plan/PlanView.swift` | read-only plan rendering |
| `Features/Settings/SettingsView.swift` | scaffold |
| `RootView.swift` | first-run → onboarding; else → latest plan; loads the catalog once |

## Build / run

Open `FitnessTracker.xcodeproj` in Xcode 26+, pick an iPhone (iOS 26) simulator,
⌘R. Tests: ⌘U (or `xcodebuild test -scheme FitnessTracker -only-testing:FitnessTrackerTests`).

## Notes for later phases

- **Xcode 26 defaults the app module to `@MainActor` isolation.** Pure-logic
  helpers (`BundledCatalog`, `PlanService`) are marked `nonisolated`; SwiftData
  `@Model` tests and `OnboardingModel` tests run `@MainActor`.
- **Local package × "Designed for iPad" destinations:** the app target's
  Supported Destinations were trimmed to iPhone/iPad only. Leaving "Mac
  (Designed for iPad)" / "Apple Vision" on made Xcode's destination
  intersection with `FitnessCore` (iOS + macOS only) empty → no run
  destinations. Don't re-add them without also widening `FitnessCore`'s
  `platforms`.

## Not yet (Phase 1c)

LLM provider adapters, `AIClient`, `PlanCoordinator` (AI generate → validate →
fallback), real-time cost metering, provider-profile UI.

## Known follow-ups

- Stub catalog → full ~120-exercise curation from `free-exercise-db` (needs the
  real equipment list).
- The engine/validator gaps in `FitnessCore/README.md` ("Known Phase 1b
  follow-ups": empty sessions, zero-volume blind spot, `sessionLengthMinutes`)
  are carried into the Phase 1c plan.
- Onboarding can currently only exclude whole muscle groups; per-exercise "won't
  do" arrives with the injury feature.
