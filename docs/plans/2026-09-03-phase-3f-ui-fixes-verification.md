# Phase 3f — UI fixes + full verification — Implementation Plan

> SDD ledger at `.superpowers/sdd/2026-09-03-phase-3f-ui-fixes-verification/`. Steps use `- [ ]`.

**Goal:** Fix the visible UI bugs, bring the finish summary to parity, and do a driven simulator walk of every screen against an acceptance checklist.

**Reference:** `~/Documents/person/opengym/frontend/src/views/Stats.jsx`, `components/Heatmap.jsx`, `views/Home.jsx`, `sheets.jsx` (`FinishSummary`). This plan is last — it depends on 3a–3e for the data behind the screens.

## Global Constraints

Phase 3 spec. App target only. No new `FitnessCore` behaviour — this consumes it. Every task ends green: `xcodebuild test …`.

## File Structure

- Modify `FitnessTracker/FitnessTracker/Features/Home/HomeView.swift` — use the single‑source streak.
- Modify `FitnessTracker/FitnessTracker/Features/History/ActivityHeatmapView.swift` — fix the shading.
- Modify `FitnessTracker/FitnessTracker/Features/Session/SessionSummaryView.swift` — finish‑summary parity.
- Modify `FitnessTracker/FitnessTracker/Features/Stats/StatsView.swift` — wire e1RM formula picker, effort histogram, recovery/strength tabs to the 3b engine.
- Create `.superpowers/sdd/2026-09-03-phase-3f-ui-fixes-verification/acceptance-checklist.md`.

---

## Task 1: Streak — one source of truth

**Files:** `HomeView.swift`, `StatsView.swift`.

- Both screens call `StreakCalculator.computeSummary(from:plannedPerWeek:weekStart:)` (from 3e Task 1). Delete any streak arithmetic living inside `HomeView`.
- Home's streak card and Stats' "Week streak" tile render the same `Summary.currentStreakWeeks`, `workoutsThisWeek`, `totalWorkouts`.

- [ ] Verify in the simulator: Home and Stats show the same streak number. Screenshot both.
- [ ] Commit `Home + Stats: single-source streak from StreakCalculator`.

## Task 2: Activity heatmap — fix the shading

**Files:** `ActivityHeatmapView.swift`.

Symptom: "35 sessions in past 52 weeks" but every cell renders the same grey.

- Build the grid as `weekStart`‑aligned columns × 7 day rows (use `WeekKey.startOfWeek`), 52–53 columns ending on the current week.
- Per day: the metric is **time trained that day** (openGym shades by minutes; sum `actualDurationMin` of that day's sessions), bucketed 0 / low / mid / high relative to the max day in the window (like the muscle map's relative levelling). 0 → the empty grey; 1–3 → the three greens.
- Likely current bugs to check: date bucketing keyed off the wrong start‑of‑day / timezone; the level function dividing by a zero max; all sessions mapping to one cell; the color ramp reading an Int where a bucket index is expected.

- [ ] Test: a `previews`/unit check with 3 fixture sessions on distinct days → 3 non‑empty cells at the right columns, the rest empty; a day with two sessions sums their minutes.
- [ ] Verify in the simulator against the demo seed: cells light up across the year. Screenshot.
- [ ] Commit `ActivityHeatmap: weekStart-aligned grid, relative day shading by minutes`.

## Task 3: Finish summary parity

**Files:** `SessionSummaryView.swift`, `SessionFinalizer.swift`/`SessionRunner.swift`.

openGym's finish summary shows, and the port should:
- tiles: duration, total volume (incl. `SetRowOps.extraVolume` from drops), sets done, PR count
- **load PRs** (heaviest working set beats the exercise's prior best) — list them
- **estimated‑1RM records**, listed **separately** (a heavier estimate without a heavier top set is "same weight, more reps" — not a load PR). Use `Estimated1RM.isRecord` (3b Task 3), and never double‑list an exercise that already appears as a load PR.
- "what you just trained" — the muscle map (`MuscleMapView`) fed this session's effective‑set load
- goal‑tinted numbers where a goal exists (body‑weight delta toward/away from target)

- [ ] Test: a session with a rep PR but no load PR → appears only under "best estimated 1RM"; a session with both → appears once, under load PR; volume includes a drop‑set's extra reps.
- [ ] Verify in the simulator: finish a demo session, check the summary. Screenshot.
- [ ] Commit `Finish summary: load PRs + separate e1RM records + muscle map + goal tint`.

## Task 4: Stats — wire the 3b engine

**Files:** `StatsView.swift`, `OpenGymLineChart.swift`, `MuscleMapView.swift`.

- e1RM section: a formula picker (Epley/Brzycki/Lombardi) driving `Estimated1RM.series`/`best`, showing the best with its **source set + date**, plus a calculator for a set not yet done, refusing > 12 reps.
- Effort card: `EffortAnalyticsEngine.computeSummary` (with the `MIN_RATED` dash), `computeWeeklyTrends` (drop‑below‑2), `computeHistogram`; a "hard sets" toggle on the muscle map filtering to `effortRIR <= 3`.
- Recovery / Strength tabs (the segmented control already exists): feed `RecoveryModel` fatigue + retained strength per muscle; "Fatigue" shades by current fatigue, "Strength" by retained strength, "Muscle balance" by effective sets in the window.
- Time windows Week / 30d / 90d / All wired to each.

- [ ] Verify in the simulator: switch formulas, switch tabs, switch windows — numbers change coherently, no crashes, the `MIN_RATED` dash shows when < 5 rated. Screenshots.
- [ ] Commit `Stats: wire e1RM formulas, effort histogram, recovery/strength/balance tabs`.

## Task 5: Driven acceptance walk

**Files:** `acceptance-checklist.md` (in the SDD workspace).

Pre‑req: macOS **Privacy → Accessibility** enabled for the terminal host so synthetic taps work (`xcrun simctl` screenshots already work). If it can't be enabled, the owner runs the checklist by hand and reports.

Walk, screenshotting each, checking against openGym behaviour:
- **Home** — week strip dots, TODAY card (rest‑day → next training day), body‑weight card + chart + goal tint, streak (== Stats).
- **Plan** — weekly grid assign/clear, per‑day reschedule, routine breakdown, generator.
- **Workout runner** — start → bodyweight prompt → rows pre‑filled with the prescription + "why" → log a set → rest timer (fires after every set) → superset round (one rest, longest member) → drop‑set sub‑row → timed hold work timer / finish early → swap exercise → reorder unit → finish prompt → summary.
- **Stats** — heatmap lit, muscle map front/back + M/F, e1RM formulas + calculator, effort card + histogram, recovery/strength tabs, windows.
- **Library** — 1,324 exercises, search, equipment filters that adapt, exercise detail, custom exercise CRUD.
- **Settings** — units, week start, rest defaults, effort scale (RIR/RPE), theme + accents, notifications toggle, backup export/import, AI providers.
- **History** — list, workout detail, "log past workout" (backfill).

- [ ] Write the checklist file with a pass/fail line per item + the screenshot path.
- [ ] Fix anything that's a one‑line gap in this plan's files; log anything larger to `docs/plans/2026-09-03-phase-3-followups.md`.
- [ ] Commit `Phase 3f: acceptance walk + checklist`.

## Task 6: Whole‑branch review

- [ ] Full suites green.
- [ ] Dispatch the whole‑branch reviewer over `fitness-engine-v2` vs `main` (per the Development Playbook §8), pointed at the Phase 3 spec + all six plans + the acceptance checklist.
- [ ] One consolidated fix wave, one scoped re‑review, adjudicate residuals.
- [ ] Commit range recorded in the ledger; carry‑forwards → `docs/plans/2026-09-03-phase-3-followups.md`.

## Self‑review

Coverage: streak parity ✅(T1), heatmap ✅(T2), finish summary ✅(T3), Stats wiring ✅(T4), full walk ✅(T5), branch review ✅(T6). No new engine — all consumes 3a–3e.
