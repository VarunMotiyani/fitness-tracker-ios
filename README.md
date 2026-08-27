# Fitness Tracker (working title)

A personal iOS app that acts as an adaptive strength & physique coach: it builds
your weekly training, tells you exactly what to do each session with the
equipment you actually have, adapts to what you actually did and how you felt,
and reads your monthly InBody scans to track whether it's working.

Built for one user (Varun), phone-only, no backend, bring-your-own AI API key.

## Status

Design phase. Nothing built yet. This repo currently holds the design docs.

## Documentation

| Doc | What's in it |
|-----|--------------|
| [docs/00-overview.md](docs/00-overview.md) | The problem, the vision, goals and non-goals |
| [docs/01-brainstorm-summary.md](docs/01-brainstorm-summary.md) | What we discussed, every decision and why |
| [docs/02-product-design.md](docs/02-product-design.md) | How the app behaves: adaptation model, onboarding, InBody, session flow, feedback loop, notifications |
| [docs/03-technical-architecture.md](docs/03-technical-architecture.md) | Stack, data model, AI contract, validation layer, failure handling, testing |
| [docs/04-roadmap-phases.md](docs/04-roadmap-phases.md) | Phase-by-phase build plan |
| [docs/05-open-questions.md](docs/05-open-questions.md) | Decisions still to make (resolved ones struck through) |
| [docs/06-decisions.md](docs/06-decisions.md) | Decision register — every settled choice, terse, in one table |
| [docs/07-exercise-dataset-research.md](docs/07-exercise-dataset-research.md) | Web research comparing exercise datasets (free-exercise-db, wger, ExerciseDB, …) and why free-exercise-db won |

## Read order

New to the project: `00` → `02` → `04`.
Picking up implementation: `03` → `04`.
