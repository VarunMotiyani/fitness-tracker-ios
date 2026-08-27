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

## Known Phase 1b follow-ups

Plan-level gaps deliberately left for the app-target phase (not defects in this package):

- **Empty sessions.** `RulePlanBuilder` keeps a session even when no catalog exercise
  matches its focus muscles (sparse catalog or heavy exclusions), and `PlanValidator`
  flags zero-item sessions. A 1b "build → validate → fall back to rules" consumer must
  handle the case where the rule plan itself has an empty session — or the curated
  `catalog.json` must cover every template focus muscle for at least one equipment subset.
- **Zero-volume blind spot.** `PlanValidator` only checks muscles that appear in the plan,
  so a muscle given no sets is not flagged. 1b/1c should validate against the intended
  target muscles, not just the observed ones.
- **`sessionLengthMinutes`** is captured in `UserContext` but unused here; 1b should size
  sessions against it.
