# Phase 3 — openGym behavioural parity — Design

**Status:** approved by owner ("i want everything") · **Branch:** `fitness-engine-v2`

## Goal

Close every behavioural and flow gap between the current Swift port and the **latest**
openGym (`~/Documents/person/opengym`, GitLab `DuarteSantos8/opengym`). The port already
has the 5‑tab UI, `FitnessCore` engine skeleton, `SessionRunner`, `RecoveryModel`,
`PlateMath`, `EffortAnalyticsEngine`, `StreakCalculator`. This phase makes the numbers and
the flows match the reference.

openGym is the behavioural spec. It is AGPL, so **no source is copied** — each task cites
the reference function whose *behaviour* it reproduces (standard training‑science method +
arithmetic), gives the Swift signature, and pins the test cases. The Swift is our own.

## Reference map (openGym file → concern)

| openGym | concern | Phase |
|---|---|---|
| `lib/progression.js` (`stallCount`, `DELOAD_AFTER`, bodyweight branch, `readSession`, `applyPrescription`, `rerampWarmups`) | progression correctness | 3a |
| `lib/rep-range.js` (`normalizeRepRange`) | double‑progression bounds | 3a |
| `lib/history.js` (`rerampWarmups`, `cascadeWeight`, `insertWarmupRow`, `MAX_PLANNED_WARMUPS`, warm‑up filtering) | warm‑up system | 3a |
| `lib/effort.js` (`rirOf`, `MIN_RATED`, `effortWeeks`, `effortHistogram`, `HARD_RIR`) | effort stats | 3b |
| `lib/onerm.js` (Epley/Brzycki/Lombardi, `REP_CAP`, `best1RM`, `is1RMRecord`) | 1RM | 3b |
| `lib/recovery.js` (`FATIGUE_HALF_LIFE_MS`, saturation curve, strength retention, states) | recovery model reconcile | 3b |
| `lib/bar.js` (`BAR_EQ`, `DEFAULT_BAR_KG/LB`, `barWeightFor`, `plateSplit`) | plate math reconcile | 3b |
| `lib/supersetFlow.js` (`restAfterSet`, `setProgressHighWater`, `restOnRecheck`, `restSecFor`, `supersetFlowStep`, `nextUnfinishedUnit`, `insertionIndexAfterCurrentUnit`) | superset + rest flow | 3c |
| `lib/workout-model.js` (`phaseForSet`, `setType`, `dropsOf`/`clustersOf`, `extraVolumeOf`, `addDrop`/`addCluster`, `nextDropWeight`, `nextBurstReps`, `splitBurstReps`, `modeForEntry`) | drop‑set / rest‑pause | 3c |
| `lib/active-workout-order.js`, `lib/active-exercise-swap.js` | mid‑workout edits | 3c |
| `lib/session-start.js` (`buildSessionEntries`), `lib/backfill.js` | shared start + log‑past | 3d |
| `lib/history.js` (`pinnedNoteFor`, `exNoteFor`, `NOTE_MAX`), `lib/finish-workout.js` (`note`, `notePin`, session note) | notes | 3e |
| `lib/history.js` (`effectiveRoutineId`, `nextTrainingDay`), `lib/week-start.js` | scheduling / day overrides | 3e |
| `views/Stats.jsx`, `components/Heatmap.jsx`, `views/Home.jsx` | UI bugs | 3f |

## Sub‑plans (each an SDD run on `fitness-engine-v2`, each leaves the app building + tests green)

- **3a — Progression engine parity** — `FitnessCore/RuleEngine` + `Metrics`. Stall
  counting + deload‑after‑N, bodyweight branch, warm‑up rows, `excludeFromProgression`,
  `normalizeRepRange`, `cascadeWeight`. Wrong‑answer bugs first.
- **3b — Metrics / recovery / plate parity** — `FitnessCore/Metrics`. RIR‑native effort +
  `MIN_RATED`, Brzycki/Lombardi + `best1RM`/`is1RMRecord`, reconcile `RecoveryModel` and
  `PlateMath` constant‑for‑constant with `recovery.js` / `bar.js`.
- **3c — Session runner: supersets, rest rules, intensifiers** — app `Session` +
  `FitnessCore`. Superset flow rules, per‑exercise `restSec`, drop‑set / rest‑pause on the
  set row, mid‑workout reorder unit + swap exercise.
- **3d — Backfill + shared session start** — app + `FitnessCore`. One `buildSessionEntries`
  path for live start and log‑past; backfill mode (no rest timers), chronological insert,
  replace‑by‑id; warm‑up seeding at start.
- **3e — Notes + scheduling** — app + `FitnessCore`. Three note types + session note +
  `NOTE_MAX`; day‑override reschedule (`dayPlan[iso]`), `nextTrainingDay`, configurable
  week start threaded through streak / heatmap / calendar.
- **3f — UI fixes + full verification** — app. Single‑source streak (Home == Stats), fix
  the dead activity heatmap, finish‑summary parity (PRs + separate e1RM records + "what you
  trained" map), then a driven simulator walk of every screen against an acceptance
  checklist.

## Global constraints (all sub‑plans)

- Branch `fitness-engine-v2`. **No `git push`.** Small commits per task.
- `FitnessCore` stays UI‑framework‑free (`Foundation` only) and Swift‑Testing‑only.
- App target default actor isolation `@MainActor`; `@Model` / `@Observable` / views `@MainActor`; pure helpers `nonisolated`.
- Persisted data model stays **openGym‑JSON compatible** (field names / shapes) so an openGym export imports unchanged.
- Every task ends green: `cd FitnessCore && swift test` and `xcodebuild test -scheme FitnessTracker -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' -project FitnessTracker/FitnessTracker.xcodeproj`.
- Snapshot types already carry `rpe`, `isWarmup`, `drops`, `clusters` (`MetricSnapshots.swift`) — extend, don't duplicate.

## Ordering

3a → 3b → 3c → 3d → 3e → 3f. 3a/3b are pure‑engine and unblock the rest. 3c depends on 3a
(warm‑up rows) and 3b (nothing hard). 3d depends on 3c (shared entry builder touches the
intensifier plan). 3e is mostly independent. 3f is last.
