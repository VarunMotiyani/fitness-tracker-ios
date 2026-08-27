# FitnessCore

Pure Swift package behind the fitness-tracker app. No SwiftUI / UIKit / SwiftData.
Builds and tests with `swift test`.

## Modules

| Module | Responsibility |
|--------|----------------|
| `FitnessDomain` | Value types: `Goal`, `ExperienceLevel`, `MuscleGroup`, `Equipment`, `UserContext`, `WeeklyPlan` + children |
| `ExerciseCatalog` | `Exercise`, `FreeExerciseDBMapper` (free-exercise-db → `Exercise`), `CatalogStore` (load / index / query) |
| `RuleEngine` | `VolumeLandmarks` (MEV/MAV/MRV table), `SplitTemplateLibrary`, `TemplateSelector`, `RulePlanBuilder` (deterministic rule-only plan) |
| `PlanValidation` | `PlanValidator` → `[ValidationIssue]` (unknown id, excluded exercise/muscle, volume out of band, empty session) |
| `LLMKit` | `LLMProvider` protocol + `LLMResult` / `LLMError` / `JSONSchema` / `ImagePayload` / `LLMCallType`. No networking — adapters live in the app target (Phase 1c). |

## Dependency line

`FitnessDomain` ← `ExerciseCatalog` ← `RuleEngine` ← `PlanValidation`
`FitnessDomain` ← `LLMKit`

## Numbers are seeds

Volume landmarks and rep ranges are starting values (spec `docs/06-decisions.md` C6),
tuned later from real training logs.
