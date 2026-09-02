# Fitness engine v2 — Design

**Status:** draft for review · **Branch:** `fitness-engine-v2` (off `main`)

## What this is

An original iOS fitness tracker: weekly plan, guided workout runner with automatic
progression, estimated 1RM, effort tracking, a muscle map, an activity heatmap, an
exercise library, and history importers — **local-first, no backend, no accounts**.

It is our own code. The training methods it implements (Epley / Brzycki / Lombardi
1RM estimators, linear / Greyskull LP / double progression, RIR↔RPE effort,
effective-set muscle volume, deload-on-stall) are published exercise-science method and
mathematics — free for anyone to implement. openGym and our existing
`FitnessCore` are **reference only**: openGym for scope and UX, `FitnessCore` for the
Swift code we already have. This is an original Swift-native implementation.

## Dataset

- **`hasaneyldrm/exercises-dataset` — MIT data.** 1,324 exercises: name, category,
  `body_part`, `equipment`, `target`, muscle groups, and **step-by-step instructions in
  10 languages** (EN/ES/IT/TR/RU/ZH/HI/PL/KO/FR). Bundled as JSON, MIT notice retained.
  Replaces `yuhonas/free-exercise-db` in `ExerciseCatalog`.
- **Media (GIF animations + thumbnails) is NOT open** — © Gym visual, redistributed in
  that repo under a repo-specific permission that does not extend to us. **Not bundled,
  not shipped.** v1 ships **no exercise imagery**; a `MediaSource` protocol leaves a seam
  for: (a) a licensed Gym visual pack later, (b) an alternative image set, (c) a
  documented runtime-hotlink stopgap with attribution. This is an open decision (§7).

## Effect on existing work

Supersedes Phases 2a–2b's engine and the in-flight Phase 2c-i (branch
`phase-2c-i-ai-session-finalize`, Task 1 at `558b27d`) — **parked, not deleted**. Its
`LLMKit` + provider adapters + `CoachMemory` are the seed for the later AI coaching
layer. `main` untouched until this branch merges.

---

## 1. Metric & logic inventory (the engine spec)

Every item is a pure, deterministic function of the workout log. Nothing is written back
into a finished workout — the next prescription is *derived* from history each time, so
editing a mistyped set or changing a policy immediately yields the right next target with
no stored counters to drift. `Have` = present in current `FitnessCore`; `Partial` =
different model, needs reconciling; `New` = to build.

### 1.1 Reading a session — `SessionReading`  *(New)*

Reduce one finished exercise entry to a verdict:

- a set marked done with **≥ target reps** → *hit*
- a set marked done with fewer reps → *miss*
- a set never marked done → *miss*
- fewer sets logged than prescribed → *miss*
- **reps mode** yields: `goal`, `reps[]` (0 for undone), top-set weight, set `count`,
  `low` (min reps), `amrap` (last set's reps — Greyskull's top set), `ok` (goal>0 and
  enough sets and every set ≥ goal)
- **time mode** yields: `goal` seconds, `held[]`, weight, `best`, `ok` (every set held ≥
  goal)
- history predating a stored prescription is judged against the exercise's *current*
  plan as the fallback target (so a long-time user isn't retroactively scored as a
  serial misser).

### 1.2 Stall counting — `stallCount`  *(New)*

Consecutive non-`ok` sessions counting back from the most recent, per exercise.

### 1.3 Progression policies — `ProgressionPolicy`  *(Partial — replaces `RuleEngine.ProgressionRule`)*

`off · linear · greyskull · double · time`. Allowed per logging mode: reps →
{off,linear,greyskull,double}; time → {off,time}; cardio → {off}. Resolution order:
**exercise override → routine default → mode default** (reps→linear, else off).

Shared constants: deload after **N consecutive misses** — linear 3, greyskull 1, double
3, time 3; deload factor **0.9**, snapped to a loadable step, never below one step, and
if 0.9× rounds back to the current load it steps down by one increment instead.

Default load increment is **body-part-aware**: heavier lifts (upper legs, lower legs,
back, hips, glutes) step 5 kg / 10 lb; everything else 2.5 kg / 5 lb. Overridable per
exercise (`inc`). Time default increment 5 s.

`nextPrescription(history, cfg, routine) → { policy, kind, weight?, reps?, sec?, sets?, why }`
where `kind ∈ first | up | hold | deload | off` and `why` is a template + args so the UI
can always answer "why this number".

- **first** (no history): baseline, no change.
- **time** — `ok` → `sec = goal + inc`. stall ≥ threshold → deload the duration. else
  hold.
- **bodyweight** (last logged working load ≤ 0 — the *trigger is the logged load, not a
  flag*, so a belted dip rejoins the weighted policies and a barbell lift logged at 0 has
  nothing to add): not `ok` or no goal → hold. Otherwise progress **reps** by the rep
  step; at a set rep ceiling, reps reset to the range bottom and a **set is added**, up
  to a 6-set cap, past which it advises "add load or a harder variation".
- **double** — fixed weight, climb a rep range. `ok` → `+inc`, reps back to range bottom.
  stall → deload, reps to bottom. else hold, aim = `min(top, max(bottom, last.low + repStep))`.
- **linear / greyskull** — `ok` → `+inc`; **greyskull double jump** when the AMRAP set hit
  ≥ 2× its target (`+2·inc`). stall ≥ threshold → deload. else hold.

`applyPrescription(sets, p)` writes only the fields a policy decided, only on not-yet-done
sets, and may grow the set list upward (bodyweight "add a set") by cloning the last row —
never shrinking a session in progress.

### 1.4 Estimated 1RM — `OneRM`  *(Partial — `Metrics.Estimated1RM` has Epley only)*

Formulas: **Epley** `w·(1+r/30)` (default), **Brzycki** `w·36/(37−r)`, **Lombardi**
`w·r^0.1`. `estimate(w, r) → nil` for load ≤ 0, reps < 1, non-finite, or **reps > 12**
(`REP_CAP` — formulas diverge and the number stops meaning maximal strength). A single
rep is returned unchanged (it's a measurement). Round to 0.1.

- `bestSet(entry)` — highest estimate among done sets; a confirmed "working weight" with
  no rep count is excluded.
- `series(exId)` — one point per workout that produced an estimate, chronological.
- `best(exId)` — all-time best **with the source set and date** ("142.5 from 100×10" ≠
  "from 140×1").
- `isRecord(exId, entry)` — beats every prior estimate (for the finish summary).

### 1.5 Muscle load — `MuscleMap`  *(Partial — `RollupComputer` does kg-based weekly volume)*

- 18 drawable muscles in head-to-toe order; an alias table folds ~59 free-text dataset
  spellings onto them (undrawable → dropped); custom exercises fall back to a body-part →
  muscle split whose weights sum to 1.
- Load is measured in **effective sets**: a target muscle counts 1.0 per set, each
  secondary muscle 0.4 (max, not summed). **kg volume is deliberately not used** — "100
  kg of leg press vs 12 kg of lateral raise says nothing about which worked harder".
- `load(items)` over `[{ exId, setCount }]`; variants for finished workouts (optionally
  filtered to hard sets), a planned routine, and a workout in progress.
- `levels(load)` — shade buckets 0–4 **relative to the hardest-worked muscle in the same
  window** (the map answers "is my training balanced", which only means anything as a
  comparison within one period).
- `rank(load)` — worked muscles descending, then untrained ones in body order (names what
  you're neglecting).

### 1.6 Effort (RIR / RPE) — `Effort`  *(New)*

Two display scales for one measurement: **RIR** counts reps left in the tank (0 = to
failure); **RPE** reads the same off a 10-point scale (RPE 8 ≡ RIR 2). A set stores
whichever scale it was logged with and is **never rewritten**. Aggregation is **internal
in RIR** (it has a real zero) and converted back for display, so a history mixing
own-logged RIR with imported RPE reads as one series.

- steppers: RIR 0–10 step 0.5, RPE 6–10 step 0.5; empty ≠ 0 (an unlogged effort must not
  become "to failure" from one tap); stepping below the floor clears the cell.
- `HARD_RIR = 3` (a set close enough to failure to drive adaptation); `MIN_RATED = 5`
  (below this an average is noise — show a dash).
- `summary(days)` → sets done, sets rated, hard count, average (nil if < 5 rated),
  hard-share — **always with the rated denominator**, since effort is opt-in and partial
  coverage is normal.
- `weeks(days)` — weekly average RIR **with that week's set count** (volume up + effort
  up = fatigue; volume up + effort flat = adaptation); weeks with < 2 rated sets dropped.
- `histogram(days)` — spread across the scale, buckets 0/1/2/3/4+ (an average hides "half
  at failure, half in warm-up territory").
- a per-exercise effort curve, and effort folded into the 1RM top-set chart (a dot fills
  in as less is left in the tank).

### 1.7 History helpers — `WorkoutHistory`  *(mostly New; some in `SessionRunner`)*

`modeOf` · `isBodyweight` (config flag, else equipment) · `isPerSide` · `sideReps` =
total/2 (shown as it falls, e.g. 8.5, so uneven sides are visible) · `repStep` = 2 for
per-side else 1 (so a target is always evenly splittable) · `mm:ss` formatting ·
set/plan one-line labels · superset-id cleanup of orphaned pairs · `lastEntry(exId)` ·
`bestWeight(exId)` (heaviest done set or the kept working weight) · `effectiveRoutine(iso)`
(day override — 'rest' or another routine — else the weekday's routine) ·
**`buildSets(cfg)`** — seed a new session from the same set *position* last time (falling
back to its final set when the plan grew), per mode; the remembered working weight
overrides for reps mode · `workoutVolume` = Σ weight×reps of done sets · `supersetUnits`
— group consecutive entries sharing a superset id · **`streakWeeks`** — consecutive ISO
weeks each containing ≥ 1 workout, counting back from now.

### 1.8 Importers — `Importers`  *(New)*

A proper CSV reader (quoted fields, embedded commas/newlines, doubled quotes, BOM, CRLF —
splitting on commas corrupts "Bench Press, Close Grip" silently). Source detection by
header for **FitNotes** (Android + iOS), **Strong**, **Hevy**, with loose fallback (date
+ exercise name + one measured value). Exercise names matched against the catalogue;
unrecognised → a custom exercise, so nothing in the file is dropped. **Apple Health** —
streaming string scan of an exported `export.xml` for body-weight records only (files run
to hundreds of MB; no DOM). `merge` folds a parsed history into the store without
overwriting.

### 1.9 Plan sharing — `PlanShare`  *(New)*

Export routines + the weekly schedule (no workouts, no weigh-ins) to a small file;
import **merges** so the recipient's plan is never overwritten. Also a clean printable
form.

### 1.10 Persisted model — `AppState`  *(Partial — SwiftData models exist; reshape)*

One local document. Fields: `unit` · `restSec` · `sound` · `keepAwake` · `lang` ·
`theme` · `accent` · `body` (male/female figure) · `targetW` (body-weight goal line) ·
`bodyweight[]` · `routines[]` (`{id, name, emoji, defaultPolicy, exercises[]}`) · `week`
(weekday → routineId) · `dayPlan` (date → routineId | rest) · `exWeights` (exId → kept
working weight + date) · `workouts[]` · `active` (live workout — device-local) ·
`customExercises[]` · `reminder` (on, time, tz) · `effortScale` (none/rir/rpe).
An exercise **config**: `exId, sets, reps, repsMin, repsMax, weight, sec, min, speed,
mode(reps/time/cardio), bodyweight, perSide, inc, policy, supersetId`. A **set**: reps
`{w, r, done, rir?/rpe?}` · time `{sec, w, done}` · cardio `{min, speed, done}`. Absent
fields read as defaults everywhere (migration-free).

---

## 2. Feature inventory & UI gaps

`FitnessCore`/Phase 2b already has: Epley 1RM, `PRDetector`, kg weekly-volume rollup,
`MetricsRepository`, a linear `ProgressionRule` (feel-driven, built for the AI coach —
**needs reconciling** with §1.3's policy model), `FinalizeGuardrail`, `VolumeLandmarks`
(MEV/MAV/MRV), split templates, `SessionRunner` + SwiftData models + Start/Focus/List/
RestTimer/Summary screens.

Gaps to build (feature → engine section):

| Area | Gap |
|---|---|
| Progression | Greyskull LP + double + time policies; deload-on-consecutive-miss; bodyweight-as-load≤0; per-side stepping; per-exercise policy override; "why this weight" surfaced on every row (§1.3) |
| 1RM | Brzycki/Lombardi; series/best-with-source/record; a calculator for sets not yet done (§1.4) |
| Muscle map | effective-set scoring + alias table + relative levels + "not trained" list; a front/back body diagram (male/female); preview while building a routine; "what you just trained" on finish (§1.5) |
| Effort | RIR/RPE logging column (opt-in); the Stats effort card, weekly chart, histogram, hard-sets muscle-map mode, per-exercise effort curve (§1.6) |
| Logging modes | timed exercises (work timer separate from rest timer), cardio (time + speed), supersets (rest only after the pair) (§1.7) |
| Planning | weekly-plan grid, per-day reschedule overrides, routine editor, exercise library with search + equipment filters that adapt to the current selection, custom exercises, plan share/print (§1.9) |
| Stats/History | activity heatmap (GitHub-style year), streak weeks, e1RM curve, per-exercise history, workout detail, body-weight chart with goal line coloured toward/away from goal |
| Import/export | FitNotes/Strong/Hevy CSV, Apple Health body weight, JSON export/import (§1.8) |
| System | rest-timer local notification, "workout planned today" reminder, screen wake-lock during a workout (toggle), sound cues |
| Presentation | light/dark + accent colours per profile, a consistent icon set, 10–12 language UI |

## 3. UI target

Information architecture and flows modelled on openGym; visuals original.

- **Tabs:** Home (today's session + body weight) · Plan (weekly grid + routines) · Stats
  (1RM · heatmap · effort · muscle map) · Library · Settings. The workout runner is a
  full-screen flow, not a tab.
- **Flows as sheets:** an `enum Sheet` on the root + `.sheet` / `.fullScreenCover`; each
  flow (bodyweight prompt, exercise picker, exercise config, routine day assign, day
  override, workout detail, calendar, import summary, finish summary, …) is a view.
- **Workout runner:** start chooser → bodyweight prompt → session built with
  `nextPrescription` already applied to the rows → per-exercise block (reps / time /
  cardio / single-stepper bodyweight / per-side) → supersets → rest timer + work timer →
  "confirm working weight" → finish summary (duration, volume, sets, PRs, 1RM records,
  muscle map).
- **Design system:** theme + accent as SwiftUI environment; `L.t(key, args…)` templated
  strings; charts hand-rolled with `Path` (no chart dependency, matches openGym's
  approach, keeps the engine + UI dependency-free).

## 4. Testing

- Engine modules (`SessionReading`, `ProgressionPolicy`, `OneRM`, `MuscleMap`, `Effort`,
  `WorkoutHistory`, `Importers`, `PlanShare`) — Swift Testing, exhaustive; this is the
  safety-critical layer. Port openGym's `*.test.js` cases as behavioural fixtures
  (expected inputs/outputs are fact, not code).
- Persistence — round-trip `AppState`; load a real openGym JSON export and assert parity
  (the model is kept compatible).
- Store — debounce, background flush, live workout survives reload.
- One XCUITest smoke: start a routine → log a set → rest timer → finish.
- No network in any test.

## 5. Phase breakdown

Each phase is one SDD run and leaves the app building (from C on, runnable).

- **A — Engine core.** All of §1 as pure modules + `AppState`/`Exercise` `Codable` + the
  MIT `exercises.json` resource + ported test suites. No app-target changes.
  Reconcile/replace the existing feel-driven `ProgressionRule`.
- **B — State & data.** `Store` + `UIStore` (`@Observable`), JSON persistence, catalogue
  load, `MediaSource` protocol (no media yet), `L.t()` + locale/instruction loading.
- **C — App shell.** TabView nav, theme/accent, the component set (button, stepper,
  number field, card, toast, icon, tab bar), empty screens.
- **D — Plan.** Weekly grid, routine editor, library + search + adaptive filters,
  exercise detail, picker, custom exercises, day overrides, plan share/print.
- **E — Workout runner.** The full core loop incl. timed/cardio modes, supersets, rest +
  work timers, wake-lock, working-weight confirm, PR + 1RM detection, finish summary.
- **F — Stats & History.** Body map + heatmap + e1RM curve/calculator + effort card /
  weekly / histogram + per-exercise history + workout detail + body-weight goal chart.
- **G — Settings & import.** All settings, the CSV + Apple Health importers with a
  confirm sheet, JSON export/import, local notifications, first-run demo seed.

## 6. Resolved decisions

1. Original implementation; standard exercise-science methods; openGym + `FitnessCore` are
   reference only.
2. `hasaneyldrm/exercises-dataset` **MIT data** replaces free-exercise-db; MIT notice
   retained.
3. **No exercise media in v1** — Gym visual media is not licensed to us. `MediaSource`
   seam left open.
4. Data model kept compatible with openGym's JSON export (free interop, and keeps the
   port honest to reference behaviour).
5. Hand-rolled charts, no chart dependency.
6. AI layer deferred; parked 2c modules are its seed.
7. Full parity is the target, delivered across phases A–G, each shippable.

## 7. Open questions

- **Exercise media** — no imagery / license Gym visual / alternative set / runtime
  hotlink stopgap. Decide before Phase D (Library).
- **Reconciling `ProgressionRule`** — the existing feel-driven rule (`Feel` easy/right/
  brutal, caps, built for the AI guardrail) vs §1.3's miss/hit + stall + policy model.
  Options: replace outright (simplest, loses the AI-tuned caps), or keep §1.3 as the
  engine and re-add the guardrail caps when the AI layer lands. Leaning replace.
- **Apple Health** — file import (openGym's route, no entitlement) vs `HealthKit` read
  (native, new entitlement + review surface). v1 = file import; HealthKit later.
- **Locale coverage at launch** — all 10 instruction languages + a UI-string set, or
  ship EN + a lazy-load path and backfill. Bundle-size call for Phase B.
- **`emoji` on routines** — openGym stores a literal emoji and maps it to an icon.
  Keep emoji, or an icon picker from the start?
