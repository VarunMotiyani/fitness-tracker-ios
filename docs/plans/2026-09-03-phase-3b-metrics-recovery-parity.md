# Phase 3b — Metrics / recovery / plate parity — Implementation Plan

> SDD ledger at `.superpowers/sdd/2026-09-03-phase-3b-metrics-recovery-parity/`. Steps use `- [ ]`.

**Goal:** Bring `FitnessCore/Metrics` to feature parity for effort analytics and 1RM, and reconcile the already‑written `RecoveryModel` / `PlateMath` against the reference so their constants and semantics match.

**Reference (read for exact constants/curves, do not copy):** `~/Documents/person/opengym/frontend/src/lib/` — `effort.js`, `onerm.js`, `recovery.js`, `bar.js`, plus their `*.test.js` for the pinned expectations.

## Global Constraints

Phase 3 spec. `FitnessCore/Metrics` only. Extend existing types — `EffortAnalyticsEngine`, `Estimated1RM`, `RecoveryModel`, `PlateMath`, `MetricSnapshots` — don't fork them.

## File Structure

- Modify `FitnessCore/Sources/Metrics/MetricSnapshots.swift` — `LoggedSetSnapshot.rir: Double?` alongside `rpe`.
- Modify `EffortAnalyticsEngine.swift` — read `rir` OR `rpe`; `MIN_RATED` floor; weekly `<2 rated` drop; histogram; per‑exercise curve.
- Modify `Estimated1RM.swift` → add Brzycki, Lombardi, `REP_CAP`, `bestSet`, `series`, `best`, `isRecord`.
- Modify `RecoveryModel.swift` — reconcile constants + saturation curve + strength retention + state thresholds.
- Modify `PlateMath.swift` — bar list, kg/lb real markings, total‑stays‑total semantics, `plateSplit`.
- Tests: extend `EffortAnalyticsEngineTests`, `Estimated1RMTests`, `RecoveryModelTests`, `PlateMathTests`.

---

## Task 1: RIR‑native effort storage

**Files:** `MetricSnapshots.swift`, `ModelSnapshotMapping.swift` (round‑trip), tests.

- Add `LoggedSetSnapshot.rir: Double?` (default nil). A set carries `rir` **or** `rpe`, never both; the one it was logged with is kept verbatim.
- Add `LoggedSetSnapshot.effortRIR: Double?` computed: `rir ?? (rpe.map { 10 - $0 })`.
- App `LoggedSetModel` gains `rir: Double?`; mapping round‑trips both.

- [ ] Tests: set logged RIR 2 → `effortRIR == 2`; set logged RPE 8 → `effortRIR == 2`; neither → nil; round‑trip through `@Model` preserves which field was set.
- [ ] Commit `Snapshot: RIR-native effort field alongside RPE`.

## Task 2: `EffortAnalyticsEngine` — coverage floor, weekly, histogram

**Files:** `EffortAnalyticsEngine.swift`, tests.

- `computeSummary`: read `effortRIR` (not `rpe` only). `hard` = `effortRIR <= HARD_RIR (3)`. **`averageRIR` and `hardSetsPercentage` are nil below `MIN_RATED` rated sets (5).** Keep `ratedSets` / `totalSets` always populated.
- `computeWeeklyTrends`: keep a week only if it has **≥ 2 rated sets**; carry that week's total set count alongside the average.
- Add `computeHistogram(sessions:windowDays:) -> [EffortHistogramBin]` — buckets 0,1,2,3 and a `4+` tail, each with count + share of rated.
- Add `exerciseCurve(exerciseID:sessions:) -> [ExerciseLoggedPerformance]` — one point per session with a top set: date, top‑set w×r, e1RM (Task 3), formatted set list, average RIR (nil if unrated).
- Windows: expose 30 / 90 / 365 / 0 (all).

- [ ] Tests: 4 rated sets → `averageRIR == nil`; 6 rated → real average; week with 1 rated set → dropped from weekly; histogram sums to `ratedSets`; a set logged in RIR and one imported in RPE average into one series.
- [ ] Commit `EffortAnalytics: MIN_RATED floor, weekly drop-below-2, histogram, exercise curve`.

## Task 3: `Estimated1RM` — Brzycki, Lombardi, series, record

**Files:** `Estimated1RM.swift`, tests.

```swift
public enum OneRMFormula: String, Sendable, CaseIterable { case epley, brzycki, lombardi }
public enum Estimated1RM {
    public static let repCap = 12
    public static func estimate(loadKg: Double, reps: Int, formula: OneRMFormula = .epley) -> Double?
    public static func bestSet(in entry: CompletedEntrySnapshot, formula: OneRMFormula) -> (est: Double, loadKg: Double, reps: Int)?
    public static func series(exerciseID: String, sessions: [CompletedSessionSnapshot], formula: OneRMFormula) -> [(date: Date, est: Double, loadKg: Double, reps: Int)]
    public static func best(exerciseID: String, sessions: [CompletedSessionSnapshot], formula: OneRMFormula) -> (est: Double, loadKg: Double, reps: Int, date: Date)?
    public static func isRecord(exerciseID: String, entry: CompletedEntrySnapshot, priorSessions: [CompletedSessionSnapshot], formula: OneRMFormula) -> (est: Double, loadKg: Double, reps: Int, previous: Double)?
}
```
Rules: `nil` for load ≤ 0, reps < 1, non‑finite, or reps > `repCap`. `reps == 1` returns the load unchanged. Round to 0.1. A confirmed "working weight" with no rep count never yields an estimate. Formulas: Brzycki `w · 36/(37−r)`, Lombardi `w · r^0.1`, Epley `w · (1 + r/30)` (already present).

- [ ] Tests: all three formulas at r=1 equal the load; `estimate(_, 13, _)` → nil; `best` returns the source set + date; `isRecord` reports `previous` and only fires when it beats every earlier estimate; `series` chronological, one point per session.
- [ ] Commit `Estimated1RM: Brzycki + Lombardi + series/best/isRecord`.

## Task 4: `RecoveryModel` reconcile

**Files:** `RecoveryModel.swift`, `RecoveryModelTests.swift`.

Read `recovery.js` and align, keeping your architecture:
- fatigue half‑life 36h; saturation `1 − exp(−stimulus / REF)` with `REF` a per‑muscle causal reference smoothed over the last N (≥3) sessions, defaulting to a fixed volume reference; bodyweight sets assume a reference load when none is logged; cardio/timed work uses a per‑minute tonnage proxy.
- strength retention: full for ~14d, then a longer half‑life decay to a floor (~0.5).
- state thresholds: `ready` below ~0.25, `recovering` ~0.25–0.5, `fatigued` above ~0.5.
- stimulus timestamp = the session's single timestamp (`start`, fallback `date`) — the same one effort uses.
- fatigue scan horizon ~30 days (beyond that a session's contribution is negligible).

Where your current constants differ, change **yours** to match and update the tests; where the reference uses a smoothed per‑muscle reference and you use a flat one, adopt the smoothed one (add `FATIGUE_MIN_SESSIONS`).

- [ ] Tests: a hard session sets fatigue in (0,1); after one half‑life the residual is ~½; after 30 days it's ~0; a muscle never trained is `ready` with retained strength at the floor; a per‑muscle reference makes a lifter's own "normal" session read ~mid‑range regardless of absolute tonnage.
- [ ] Commit `RecoveryModel: reconcile constants + saturation + per-muscle reference`.

## Task 5: `PlateMath` reconcile

**Files:** `PlateMath.swift`, `PlateMathTests.swift`.

- `usesBar(exercise)` for equipment in {barbell, olympic barbell, ez barbell, smith machine, trap bar}.
- Bar defaults **per unit, as real markings** (not conversions): the kg set and the lb set are independent tables.
- `barWeightFor(state, exercise)` — the user's per‑exercise override if set, else the equipment default for the profile unit, else nil.
- **Logged weight stays the total on the bar** — history, progression, 1RM all keep reading the total. Bar weight is display metadata only.
- `plateSplit(total, bar) -> Double?` = `(total − bar) / 2` rounded to 2 dp; nil when total ≤ bar or either missing.
- Keep the plate‑breakdown (which discs per side) you already have; feed it `plateSplit`.

- [ ] Tests: barbell kg default 20, lb default 45 (independent); override wins; `plateSplit(100, 20) == 40`; `plateSplit(20, 20) == nil`; a non‑bar exercise → `barWeightFor == nil`; total is never mutated by any of this.
- [ ] Commit `PlateMath: bar table per unit, total-stays-total, plateSplit`.

## Task 6: Suite sweep

- [ ] `cd FitnessCore && swift test` + `xcodebuild test …` green. Update any test that asserted the old RPE‑only / Epley‑only / old‑recovery behaviour, in the task that changed it.
- [ ] Commit `Phase 3b: suites green`.

## Self‑review

Coverage: RIR‑native ✅(T1), MIN_RATED + weekly + histogram + curve ✅(T2), Brzycki/Lombardi + best/isRecord ✅(T3), recovery reconcile ✅(T4), plate reconcile ✅(T5). Types: `effortRIR` from T1 used by T2/T3; `OneRMFormula` from T3 used by T2's curve.
