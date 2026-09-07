# Phase 3a — Progression engine parity — Implementation Plan

> **For agentic workers:** SDD ledger at `.superpowers/sdd/2026-09-03-phase-3a-progression-parity/`. Steps use `- [ ]`.

**Goal:** Make `FitnessCore` progression produce the same target/why as openGym `lib/progression.js` for every policy, including stall counting, per‑policy deload, the bodyweight branch, and warm‑up handling.

**Architecture:** A new pure `SessionReading` type reduces a completed entry to a verdict. `ProgressionRule.next(...)` gains a `history: [SessionReading]` input and a `stallCount`. Warm‑up rows (`LoggedSetSnapshot.isWarmup`) are filtered wherever `ok`/`low`/`count` are computed. Nothing writes back to a finished session.

**Spec:** `docs/specs/2026-09-03-opengym-parity-phase3-design.md`. Reference: `~/Documents/person/opengym/frontend/src/lib/progression.js`, `lib/rep-range.js`, `lib/history.js` (`rerampWarmups`, `cascadeWeight`).

## Global Constraints

Per the Phase 3 spec. `FitnessCore` only in this plan (no app‑target changes). Existing `ProgressionRuleTests` must stay green or be updated in the same task that changes behaviour.

## File Structure

- Create `FitnessCore/Sources/RuleEngine/SessionReading.swift` — the verdict type + reducer.
- Create `FitnessCore/Sources/RuleEngine/RepRangeNormalize.swift` — `normalizeRepRange`.
- Create `FitnessCore/Sources/RuleEngine/WarmupRamp.swift` — `rerampWarmups`, `cascadeWeight`.
- Modify `FitnessCore/Sources/RuleEngine/ProgressionRule.swift` — stall counting, deload‑after‑N, bodyweight branch, `first` kind, `excludeFromProgression` filter, `why` as a template.
- Modify `FitnessCore/Sources/Metrics/MetricSnapshots.swift` — add `CompletedSessionSnapshot.excludeFromProgression: Bool = false`.
- Tests: `SessionReadingTests.swift`, `RepRangeNormalizeTests.swift`, `WarmupRampTests.swift`, extend `ProgressionRuleTests.swift`.

---

## Task 1: `SessionReading` — reduce a completed entry to a verdict

**Files:** create `SessionReading.swift`; test `SessionReadingTests.swift`.

**Produces:**
```swift
public struct SessionReading: Sendable, Equatable {
    public enum Mode: Sendable { case reps, time, cardio }
    public let mode: Mode
    public let goal: Int          // target reps (reps) or target seconds (time)
    public let repsPerSet: [Int]  // 0 for an undone set; work rows only
    public let heldPerSet: [Int]  // time mode
    public let weight: Double     // max done work-set load
    public let count: Int         // work-set count (the dimension bodyweight grows)
    public let low: Int           // min reps across work sets
    public let amrap: Int         // last work set's reps (Greyskull top set)
    public let ok: Bool
    public let date: Date
}

public enum SessionReadingReducer {
    /// Warm-up rows (`isWarmup`) are dropped first. `plannedSets` falls back to the
    /// entry's own set count when the stored target has none. `ok` = goal>0 AND
    /// setsLogged >= plannedSets AND every work set met the goal.
    public static func read(entry: CompletedEntrySnapshot,
                            target: PrescriptionTarget,
                            fallbackTarget: PrescriptionTarget?,
                            date: Date) -> SessionReading

    /// Oldest-first readings for one exercise across a session history, skipping
    /// sessions flagged `excludeFromProgression` and entries with no done work set.
    public static func history(exerciseID: String,
                               sessions: [CompletedSessionSnapshot],
                               currentTarget: PrescriptionTarget) -> [SessionReading]

    /// Consecutive non-`ok` readings counting back from the most recent.
    public static func stallCount(_ readings: [SessionReading]) -> Int
}
```
`PrescriptionTarget` = the existing plan-item shape (sets, reps, repsMin/Max, load, sec, mode, perSide, policy, inc). Reuse `RepRange` where it fits; add a small struct if not.

**Behaviour:** mirrors `readSession` / `sessionsFor` / `stallCount` in `progression.js` (lines ~103–156). Honesty rules: done set with reps ≥ goal → counts to `ok`; done with fewer → miss; undone → 0 reps, miss; fewer sets than planned → `enough=false` → miss.

- [ ] **Step 1** Write `SessionReadingTests`:
  - all sets done at goal, correct count → `ok == true`
  - one set at goal‑1 → `ok == false`, `low == goal‑1`
  - 2 sets logged of 3 planned → `ok == false`
  - one undone warm‑up + 3 done work sets at goal → `ok == true`, `count == 3`, warm‑up ignored
  - `amrap` == last work set reps; `weight` == max done load
  - time mode: every set held ≥ goal → `ok`
  - `history(...)` skips a session with `excludeFromProgression == true`
  - `stallCount`: readings `[ok, miss, miss]` → 2; `[miss, ok, miss]` → 1; `[ok, ok]` → 0
- [ ] **Step 2** Run, watch fail.
- [ ] **Step 3** Implement.
- [ ] **Step 4** `cd FitnessCore && swift test --filter SessionReading` green.
- [ ] **Step 5** Commit `Add SessionReading verdict reducer + stall counting`.

## Task 2: `normalizeRepRange`

**Files:** create `RepRangeNormalize.swift`; test `RepRangeNormalizeTests.swift`.

**Produces:**
```swift
public enum RepRangeNormalize {
    /// upper defaults to 10; lower defaults to max(1, upper-2). Both ceil-aligned to
    /// `stride` (stride 2 for per-side). If lower >= upper, returns (repsMin: lower,
    /// reps: lower + stride).
    public static func normalize(reps: Int?, repsMin: Int?, stride: Int) -> (repsMin: Int, reps: Int)
}
```
**Behaviour:** `lib/rep-range.js` `normalizeRepRange`.

- [ ] Tests: `(nil, nil, 1)` → `(8, 10)`; `(12, 8, 1)` → `(8, 12)`; `(10, 10, 1)` → `(10, 11)`; `(15, nil, 2)` → `(14, 16)` (`repsMin = align(13,2)=14`, wait: upper=align(15,2)=16, lower default max(1,16-2)=14 → `(14,16)`); `(5, 9, 2)` → lower 10 ≥ upper 6 → `(10, 12)`.
- [ ] Implement, test green, commit `Add normalizeRepRange for double progression bounds`.

## Task 3: Stall counting + per‑policy deload into `ProgressionRule`

**Files:** modify `ProgressionRule.swift`; extend `ProgressionRuleTests.swift`.

**Change `next(...)` signature** to take history:
```swift
public func next(
    current: PrescriptionTarget,
    mechanic: Mechanic,
    history: [SessionReading],          // oldest-first, this exercise, this mode
    unit: MassUnit = .kg
) -> Prescription
```
```swift
public struct Prescription: Sendable, Equatable {
    public enum Kind: Sendable { case first, up, hold, deload, off }
    public let policy: ProgressionPolicy
    public let kind: Kind
    public let weightKg: Double?
    public let reps: Int?
    public let sets: Int?
    public let sec: Int?
    public let why: WhyTemplate            // template id + args, for localisation
}
```

**Behaviour** — `nextPrescription` in `progression.js` (lines 166–253):
- `policy == off` → `.off`.
- no history → `.first`, why "baseline".
- `deloadAt = DELOAD_AFTER[policy]` = **linear 3, greyskull 1, double 3, time 3**. `deloadFactor = 0.9`.
- `deloadTo(cur, step)`: `snap(cur*0.9, step)`; if `≥ cur` → `snap(cur - step, step)`; floor at `step`.
- **time**: `last.ok` → `sec = (last.goal ?: cfg.sec) + inc` (`inc = 5s`). `stalls >= deloadAt` → deload sec via `deloadTo(_, 5)`. else hold.
- **bodyweight** (`last.weight <= 0`, runs before the policy switch): see Task 4.
- **double**: range via `normalizeRepRange`. `last.ok` → `weight = snap(w+inc, inc)`, `reps = bottom`. `stalls >= deloadAt` → `deloadTo(w, inc)`, `reps = bottom`. else hold, `reps = min(top, max(bottom, last.low + repStep))`.
- **linear + greyskull**: `last.ok` → up by `inc`; **greyskull double jump** when `last.goal > 0 && last.amrap >= last.goal*2` → `+2*inc`. `stalls >= deloadAt` → `deloadTo(w, inc)`. else hold, why carries `(deloadAt - stalls)` remaining.
- `inc = cfg.inc>0 ? cfg.inc : defaultIncrement`. `defaultIncrement`: HEAVY body parts (`upper legs, lower legs, back, hips, glutes`) → lb 10 / kg 5; else lb 5 / kg 2.5.
- `snap(v, step) = round(v/step)*step` (1 dp).

**Keep** the existing feel‑driven `standardLinear` **as a distinct policy** (`ProgressionPolicy.aiCoach` or keep `standardLinear`) — the AI layer wants it. Add openGym's `linear` as a separate case. So `ProgressionPolicy` becomes `{ off, linear, greyskull, double, time, aiCoachLinear }`.

- [ ] Tests (extend `ProgressionRuleTests`):
  - linear: `[miss]` → `.hold` (1/3), `[miss, miss]` → `.hold` (2/3), `[miss, miss, miss]` → `.deload` at `deloadTo(w, inc)`
  - greyskull: single `[miss]` → `.deload` (deloadAt 1)
  - greyskull: `last.ok`, `amrap == goal*2` → `.up` by `2*inc`
  - double: `last.ok` → `.up`, `reps == bottom`; stall×3 → `.deload`, `reps == bottom`; hold → `reps == min(top, last.low + repStep)`
  - time: `last.ok` → `sec += 5`; stall×3 → deload
  - `deloadTo`: small weight where `0.9*` rounds back → steps down one `step`; floor at `step`
  - `defaultIncrement`: `back` compound kg → 5; `chest` isolation kg → 2.5; lb doubles
- [ ] Implement; update call sites in `SessionFinalizer.swift` / wherever `ProgressionRule().next` is called (pass `history`). If that touches the app target, split into a follow‑up task noted in the ledger.
- [ ] `swift test` green; commit `ProgressionRule: stall counting + per-policy deload + double/greyskull/time`.

## Task 4: Bodyweight branch (logged load ≤ 0)

**Files:** modify `ProgressionRule.swift`; extend tests.

**Behaviour** — `progression.js` lines 198–216. Runs **before** the policy switch, for every policy, when `last.weight <= 0`:
- `goal = last.goal ?: cfg.reps`. If `!last.ok || goal <= 0` → `.hold(weight: 0, reps: goal)`, why "same target until every set is clean".
- Rep ceiling `top = cfg.repsMax > 0 ? cfg.repsMax : 0`. If `top > 0 && goal >= top`:
  - `sets = max(1, cfg.sets ?: last.count) + 1`, `bottom = max(1, min(cfg.reps ?: top, top))`.
  - `sets <= MAX_BW_SETS (6)` → `.up(weight: 0, reps: bottom, sets: sets)`, why "N reps every set — add a set, back to bottom".
  - else → `.hold(weight: 0, reps: goal)`, why "N sets of M — add weight or a harder variation".
- Otherwise → `.up(weight: 0, reps: goal + repStep(cfg))` where `repStep = cfg.perSide ? 2 : 1`. why "every rep last time — go for X".

- [ ] Tests:
  - bw, `last.ok`, `goal < top` → `.up`, `reps == goal + 1`
  - bw per‑side, `last.ok` → `reps == goal + 2`
  - bw, `goal >= top`, `sets+1 <= 6` → `.up`, `sets` incremented, `reps == bottom`
  - bw, `goal >= top`, `sets+1 > 6` → `.hold`, why "add weight / harder variation"
  - bw, `!last.ok` → `.hold(weight: 0)`
  - belted dip (`last.weight > 0`) → falls through to the normal policy (NOT the bw branch)
- [ ] Implement; `swift test` green; commit `ProgressionRule: bodyweight rep progression (load<=0)`.

## Task 5: `excludeFromProgression`

**Files:** modify `MetricSnapshots.swift` (`CompletedSessionSnapshot.excludeFromProgression: Bool = false`), `ModelSnapshotMapping.swift` if a `@Model` field is needed (note in ledger if it crosses to the app target — if so, split), `SessionReadingReducer.history` (already skips it per Task 1).

**Behaviour** — `sessionsFor` line 141: a session with `excludeFromProgression == true` is real history for stats but never a progression baseline.

- [ ] Test: `history(...)` with 3 sessions, middle one flagged → returns 2 readings, baseline = the 2nd‑newest unflagged.
- [ ] Implement; green; commit `Snapshot: excludeFromProgression flag, skipped by progression history`.

## Task 6: `WarmupRamp` — `rerampWarmups` + `cascadeWeight`

**Files:** create `WarmupRamp.swift`; test `WarmupRampTests.swift`.

**Produces:**
```swift
public enum WarmupRamp {
    /// After a prescription sets the work rows' final weight, re-ramp the leading
    /// warm-up rows toward it (percentage ladder, snapped to `step`). Work rows and
    /// done rows untouched. Mirrors history.js `rerampWarmups`.
    public static func reramp(rows: [SetRow], step: Double) -> [SetRow]

    /// Editing row `from`'s weight cascades the new value to every later NOT-done,
    /// NOT-warmup row that still held the old value. Mirrors history.js `cascadeWeight`.
    public static func cascadeWeight(rows: [SetRow], from index: Int, value: Double) -> [SetRow]
}
```
`SetRow` = the working row shape used by `SessionRunner` (w, r, sec, done, isWarmup, type). If that lives in the app target, put `WarmupRamp` operating on `LoggedSetSnapshot` in `FitnessCore` and adapt at the call site; note the boundary in the ledger.

**Behaviour:** read `history.js` `rerampWarmups` (line ~531) and `cascadeWeight` (line ~493) for the exact ladder and the "still held the old value" guard.

- [ ] Tests:
  - 2 warm‑ups + 3 work rows at 100 → reramp produces an ascending ladder ≤ 100, snapped to `step`, work rows unchanged
  - editing row 0 from 100→110 cascades to rows 1,2 (which were 100) but not row 3 (which the user set to 105) and not a done row
- [ ] Implement; green; commit `Add WarmupRamp: reramp + cascadeWeight`.

## Task 7: Wire `first` / `why` templates + regression sweep

**Files:** modify `ProgressionRule.swift` (finalise `WhyTemplate` cases), update `SessionFinalizer.swift` to render `why` to `perItemRationale` string, run full suites.

- [ ] `WhyTemplate` enum with one case per `why` string in `progression.js` (`baseline`, `everyRepAddLoad`, `greyskullDoubleJump`, `missedHold`, `missedDeload`, `bwAddSet`, `bwAddWeightOrHarder`, `bwMoreReps`, `timeUp`, `timeDeload`, `doubleUp`, `doubleHold`, `doubleDeload`). Each with typed args.
- [ ] A `render(_:unit:) -> String` producing the English text (localise later).
- [ ] `SessionFinalizer` maps `Prescription.why` → the entry rationale.
- [ ] Full: `cd FitnessCore && swift test` + `xcodebuild test …` green.
- [ ] Commit `Progression why-templates + finalizer wiring; suites green`.

## Self‑review

Spec coverage: stall/deload ✅ (T3), bodyweight ✅ (T4), warm‑up filter in readings ✅ (T1) + reramp ✅ (T6), `excludeFromProgression` ✅ (T5), `normalizeRepRange` ✅ (T2), `cascadeWeight` ✅ (T6), `first` kind + why ✅ (T7). Placeholder scan: every task has concrete test cases + a cited reference function. Type consistency: `SessionReading` (T1) is consumed by `ProgressionRule.next` (T3/T4); `PrescriptionTarget` defined once in T1.
