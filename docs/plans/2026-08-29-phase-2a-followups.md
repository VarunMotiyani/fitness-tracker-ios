# Phase 2a — carried-forward follow-ups

Committed copy of the deferred/parked items from the Phase 2a SDD run (the SDD
ledger under `.superpowers/` is gitignored and does not travel between machines).
All of these are **Minor** — Phase 2a's whole-branch Opus review was "merge with
fixes"; the 1 Critical + 8 Important were all fixed in the 9-commit fix wave and
a scoped re-review came back clean. What remains is listed here so 2b/2c/2d pick
it up rather than rediscovering it.

Branch: `phase-2a-metrics-memory-foundation` @ `2f91336` (+ a HANDOFF doc commit).
126 `FitnessCore` tests green. Package-only — no app changes.

## Still open after the fix wave

### For Phase 2b (persistence layer)
- **R1 — dangling `supersededBy`.** In `MemoryConsolidation.reconcile`, a
  `.contradicts(id)` candidate whose *fresh write* is itself cap-evicted in the
  same call leaves the superseded pre-existing memory in `retired` with a
  `supersededBy` pointing at an id that appears in no output array. The 2b
  persistence layer must tolerate a `supersededBy` that resolves to nothing
  (treat as "retired, no successor recorded"). Narrow path; pre-existing, not
  introduced by the fix wave.
- **`MemorySource` wire format.** `enum MemorySource { case agent(String); case user }`
  currently uses Swift's synthesised enum-with-payload `Codable`
  (`{"agent":{"_0":"..."}}` — asserted verbatim in a test). Fine in-process,
  brittle as a persisted shape. When 2b maps `CoachMemory` to/from a SwiftData
  `@Model`, give `MemorySource` a hand-written flat `Codable`
  (`{"kind":"agent","name":"..."}`) or store it as two columns.
- **Snapshot ↔ `@Model` mapping.** The `Metrics` value types (`*Snapshot`,
  `PersonalRecord`, `WeeklyMuscleVolume`, `ExerciseTrendPoint`,
  `ExercisePerformance`) are all `let` structs with full memberwise inits and now
  all `Codable` — they map cleanly from `@Model` classes. `CoachMemory` has a
  custom `init(from:)` (for `retiredByCap` forward-compat) — mirror that logic in
  the `@Model` mapping.

### For Phase 2c (AI coach agents)
- **R2 — light-load clamp can go backwards.** `FinalizeGuardrail`'s
  `floorToStep(last * (1 + maxIncreaseFraction))` can, for a prior working load
  below ~25 kg, cap a too-large proposed *increase* to a value *below* the prior
  load (e.g. last 11 kg → capped 10 kg). Only bites for very light loads + a
  >10% proposed jump. Fix when 2c first consumes the guardrail:
  `cappedKg = max(roundedCap, roundToStep(last))` on the increase side.
- **ProgressionRule edge behaviours are unguarded by tests.** `brutal` + a rep
  *above* `repRange.max` still `.decreaseLoad`; empty working-set list →
  `.hold`; `feel == nil` direction. The fix wave added tests for the first two;
  `feel == nil` mid-range is covered. If 2c relies on any of these, add an
  explicit assertion.
- **`MemoryConsolidation` needs a `source` for user-authored memories.**
  `reconcile` hard-codes `.agent("memoryKeeper")` on everything it writes. When
  the app lets the user type "tell the coach: ...", either add
  `source: MemorySource = .agent("memoryKeeper")` as a `reconcile` parameter or a
  `source` field on `MemoryCandidate`.
- **`writes` array ordering.** `MemoryConsolidation` output arrays are a total
  order *as sets* but the sequence of `writes` depends on freshly-generated
  UUIDs (all share `createdAt == now`). Deterministic for a fixed UUID sequence,
  not across runs. If candidate order must survive, carry an index on
  `MemoryCandidate` and sort on it.

### For Phase 2d (history views)
- **T5 — window vs bucket misalignment.** `MetricsRepository.weeklyVolume(weeks:)`
  and `adherence(weeks:)` define the window as `weeks * 7` days back from `now`,
  which is not snapped to the ISO week buckets `RollupComputer` emits. For some
  `now` weekdays this yields `weeks + 1` partial buckets. Either snap
  `windowStart` to `Calendar.isoUTC.dateInterval(of: .weekOfYear, for: now)!.start`
  minus `(weeks - 1)` weeks, or document the off-by-one where the history view
  consumes it.

## Cosmetic / non-blocking (do when touching the file)
- **R3** — `FinalizeGuardrail`'s weekly-volume-proxy note is `///` but sits
  inside a function body, so it's an ordinary comment (no quick-help). Move it to
  a declaration or make it `//`.
- **R4** — `ProgressionRuleTests.capsBindWhenTight` decrease branch: with the
  artificial 1% floor the result rounds back to the current load while
  `direction == .decreaseLoad`; the `> current * 0.95` assertion passes without a
  real decrease. Tighten or annotate as a test-only artifact.
- **R5** — `Rollups.swift` `exerciseTrend` still has a `var bestE1RM = -1.0`
  sentinel (harmless: `workingSets` is guarded non-empty and Epley ≥ 0). Left
  inconsistent with `PRDetector`'s fix-wave cleanup; align for readability.
- **T3** — `PRDetector` cross-session `repsAtWeight` load match uses exact
  `Double ==`. Correct for 2.5 kg-stepped plate loads; a silent miss the moment
  percentage-of-1RM or lb↔kg-converted loads exist. Switch to
  `abs(a - b) < 0.001` before any computed-load path lands.
- **`stalls()`** recomputes the full per-exercise trend inside a `filter`
  (O(exercises × sessions × entries)). Trivial at personal-log scale; group once
  if it ever matters.
