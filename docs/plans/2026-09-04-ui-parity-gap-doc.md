# UI Parity Gap Doc — PulseAI vs. openGym

A screen-by-screen catalogue of what the openGym web app does that the Swift app does not
yet, why it matters, where the behaviour is defined in the openGym reference checkout
(`~/Documents/person/opengym`), and how to build it natively in SwiftUI.

**How to read the "openGym ref" column:** it is a *pointer* into the reference codebase so
you can see the intended behaviour, not code to translate. Every "How to add" section is
an original SwiftUI design implementing a standard app pattern (a reorderable list, a
segmented control, a set-logging table) or a standard training method — none of it is a
port of openGym's source.

**Engine status:** most of the pure logic already exists in `FitnessCore` (written in the
parallel pass): `SessionReading`, `ProgressionRule.next(current:mechanic:history:)`,
`RepRangeNormalize`, `WarmupRamp`, `SupersetFlow`, `SetRowOps`, `ActiveWorkoutEdits`,
`SessionEntryBuilder`, `BackfillOps`, `Notes`, `Scheduling`, `WeekKey`,
`EffortAnalyticsEngine`, `Estimated1RM`, `RecoveryModel`, `PlateMath`, `StreakCalculator`.
Much of the work below is **wiring existing helpers into views**, not new logic.

---

## Contents

1. Routine management (RoutineEdit, ExerciseConfig, Plan rework, plan sharing, icon picker)
2. Workout runner
3. Stats
4. Settings
5. Home polish
6. Backfill — log a past workout
7. Cross-cutting: data model, components, wiring checklist

---

## 1. Routine management

The single largest hole. Today `PlanView.swift` is a read-only render of the AI-generated
`WeeklyPlan`; there is no way to create, name, reorder, or configure a routine.

### 1.1 RoutineEditView — the routine editor screen

| | |
|---|---|
| **Screen** | New. Reached from Plan → tap a routine, or Plan → "+ New". Route: a `.navigationDestination` on the Plan tab's `NavigationStack`. |
| **What it does** | Edit one routine: rename, pick an icon, add/remove exercises, drag to reorder, link exercises into supersets, set a routine-level progression policy, mark the whole routine "excluded from automatic progression" (planned deload), preview which muscles the session hits, delete the routine. |
| **Status** | Missing entirely. `PlanView.swift` has no editor; tapping a row calls `onStartSession`. |
| **openGym ref** | `views/RoutineEdit.jsx` — the header (name `<input>` + `glyphPicker` button), the `SelectRow` "Progression" + `Switch` "Exclude from automatic progression", the `useRoutineReorder` drag hook, the exercise-row block (thumbnail, `exLine` summary, link/move buttons, `Superset` group label), the "What this session hits" `BodyMap` block, and the "Add exercise" / "Delete routine" buttons at the bottom. `sheets.jsx` → `glyphPicker`. |
| **How to add** | Create `Features/Plan/RoutineEditView.swift`. State: a working copy `@State var routine: RoutineDraft` (see §7.1 for the model). Layout, top→bottom: <br>• **Header row**: back chevron, `TextField("Routine name", text: $routine.name)` styled large; a trailing `Button` opening `IconPickerSheet` (§1.5). <br>• **Progression section**: a `Picker`/menu bound to `routine.policy` over `ProgressionPolicy.allCases` filtered to `POLICIES_FOR[mode]`; a `Toggle("Exclude from automatic progression", isOn: $routine.excludeFromProgression)` with a caption. <br>• **Equipment-warning card** (optional): if any exercise needs kit outside the active `EquipmentProfile`, show an orange card "N of M exercises need equipment you don't have". <br>• **Exercise list**: `List { ForEach(routine.exercises) … }.onMove(perform:)` inside `.environment(\.editMode, .constant(.active))` (or a custom long-press drag with `.draggable`/`.dropDestination` if you want openGym's live-follow feel). Each row: `ExerciseThumbnailView`, name, a summary line built by a Swift `exerciseSummary(config:unit:)` (sets × reps [· load] [· "8/side"] [· mm:ss]), an inline note if present. Trailing controls per row: a **link button** (`link.circle`) that toggles a superset with the row above (writes a shared `supersetID`), and `chevron.up`/`chevron.down` that move the row's whole superset *unit* (use `ActiveWorkoutEdits.units(...)`-style grouping or a local `supersetUnits`). A `Label("Superset", systemImage: "link")` header above the first row of each multi-member group. Tapping a row opens `ExerciseConfigSheet` (§1.2). Swipe-to-delete calls `cleanupSupersets` after removal. <br>• **"What this session hits"**: reuse `MuscleMapView` fed `MuscleMap.loadOfRoutine(...)`-style effective-set load from the routine's exercises; a wrap of muscle chips for the top ~6. <br>• **Add exercise**: `Button` → `ExercisePickerSheet` (you have picker logic in `LibraryView`; extract a reusable `ExercisePickerSheet`) → on pick, open `ExerciseConfigSheet` with a fresh default config → append. <br>• **Delete routine**: destructive `Button` → `confirmationDialog` → remove from the plan/store, pop. <br>On disappear or on each edit, persist the draft back to the routine model (`@Model` or the plan JSON — see §7.1). |
| **Tests** | Superset link/unlink keeps groups contiguous; move-unit keeps a 2-member group together; delete + `cleanupSupersets` drops an orphaned `supersetID`; the muscle preview updates when an exercise is added. |

### 1.2 ExerciseConfigSheet — per-exercise configuration

| | |
|---|---|
| **Screen** | Sheet. Opened from RoutineEdit (tap a row / add) and from Library's "+ Plan". |
| **What it does** | Configure one exercise inside a routine: **sets**, **reps** (single target) or a **rep range** (min–max for double progression), **working weight**, **rest seconds**, **logging mode** (reps / time / cardio), **bodyweight** flag, **per-side** flag, **superset** membership, a **per-exercise progression-policy override**, and a **load-increment override**. |
| **Status** | Missing entirely. |
| **openGym ref** | `sheets.jsx` → `exConfigSheet` and its `ProgressionFields` sub-component (policy picker + increment + rep-range inputs); `lib/history.js` → `defaultConfig`; `lib/rep-range.js` → `normalizeRepRange` (already ported as `RepRangeNormalize`). |
| **How to add** | `Features/Plan/ExerciseConfigSheet.swift`, a `Form` in a `.sheet` with a bound `ExerciseConfig` (§7.1). Fields: <br>• **Mode** — `Picker("Logging", selection:)` [Reps · Time · Cardio]; switching mode swaps the fields below. <br>• Reps mode: `Stepper` sets; a toggle "Use a rep range"; if off → `Stepper` target reps; if on → two `Stepper`s min/max, normalized on commit via `RepRangeNormalize.normalize(reps:repsMin:stride:)` (stride 2 when per-side). `NumberField` working weight (kg/lb per profile). `Stepper` rest seconds (5s steps, "Off" at 0). <br>• Time mode: `Stepper` target seconds, optional added weight. <br>• Cardio mode: duration + speed. <br>• **Toggles**: "Bodyweight (no external load)" and "Reps per side" — both write `config.bodyweight` / `config.perSide`. Seed `bodyweight` from the exercise's equipment when the sheet first opens. <br>• **Progression override**: `Picker` over the allowed policies for the mode, plus a "Use routine default" option (nil). `NumberField` "Load increment" with placeholder = `ProgressionRule.defaultIncrement(bodyPart:unit:)`. <br>• Save writes the config back; Cancel discards. |
| **Tests** | Range normalization on save; mode switch clears the irrelevant fields; bodyweight seeded from equipment; "use routine default" stores nil policy. |

### 1.3 PlanView rework — schedule + routine list

| | |
|---|---|
| **Screen** | The Plan tab (`Features/Plan/PlanView.swift`). |
| **What it does** | Two sections. **Week schedule**: seven weekday rows (order depends on the week-start setting), each showing its assigned routine as a chip (or "Rest"); tapping a row opens an **assign** picker (choose a routine or Rest for that weekday). **Routines**: every routine as a card (icon, name, "N exercises"); tapping opens RoutineEdit; a **"+ New"** button; an empty state with "Load starter plan". A header **share/export** button. |
| **Status** | Partial. Your `PlanView` renders `plan.sessions` as read-only "Session N" rows and a "WEEKLY VOLUME TARGETS" section (keep that — it's your AI artefact). No weekday→routine assignment, no "+ New", no editor link, no share. |
| **openGym ref** | `views/Plan.jsx` — the "Week schedule" list (`weekOrder(weekStartOf(S)).map` → `dayAssignSheet`), the "Routines" section with the "New" button and `addRoutine`, the empty state, and the header `planToolsSheet` button. `sheets.jsx` → `dayAssignSheet`. |
| **How to add** | In `PlanView.swift`: wrap in a `NavigationStack` with a `navigationDestination(for: RoutineID.self) { RoutineEditView(id: $0) }`. <br>• **Week schedule**: `ForEach(WeekKey.orderedWeekdays(weekStart:))` → row with weekday name + assigned-routine chip; `.onTapGesture` presents `DayAssignSheet` (a sheet listing all routines + "Rest" + "Clear"); the choice writes `week[weekday] = routineID?` in the store (§7.1). <br>• **Routines**: `ForEach(routines)` → `NavigationLink(value: routine.id)` card. A toolbar or section-header `Button("＋ New")` that creates a blank routine and pushes RoutineEditView. Empty state → "Load starter plan (PPL)" button seeding the three PPL routines. <br>• **Header**: a toolbar `Button` (`square.and.arrow.up`) → `PlanShareSheet` (§1.4). |

### 1.4 PlanShareSheet — export / print / import a plan

| | |
|---|---|
| **Screen** | Sheet from PlanView header. |
| **What it does** | Export routines + the weekly schedule (no workouts, no weigh-ins) as a small file to share; print a clean PDF of the plan; import a plan file, **merging** so the recipient's own routines are not overwritten. |
| **Status** | Missing. |
| **openGym ref** | `sheets.jsx` → `planToolsSheet`, `planImportSheet`; `lib/plan-share.js` (encode/merge). |
| **How to add** | Build `FitnessCore/Sources/RuleEngine/PlanShare.swift` (pure): `struct SharedPlan: Codable` = `{ routines, week }`; `encode(routines:week:) -> Data`; `merge(into:from:) -> (routines, week)` that appends imported routines with fresh IDs and only fills empty weekday slots. UI: `PlanShareSheet` with a `ShareLink(item:)` for the file, a "Print" button (`UIPrintInteractionController` or a rendered `View` → PDF), and a `.fileImporter` whose result is `merge`d. |
| **Tests** | `merge` never overwrites an existing routine or a filled weekday; round-trip `encode`→decode is stable. |

### 1.5 IconPickerSheet — routine icon

| | |
|---|---|
| **Screen** | Sheet from RoutineEdit header. |
| **What it does** | Pick a small glyph for the routine (shown on Home, Plan, the week strip). |
| **Status** | Missing. Your routine model has no icon field. |
| **openGym ref** | `sheets.jsx` → `glyphPicker`; `lib/glyphs.js` (the glyph set + `glyphOf`). |
| **How to add** | Define a fixed set of SF Symbols (`["figure.strengthtraining.traditional", "figure.core.training", "figure.run", "dumbbell.fill", …]`) as `RoutineIcon` cases. `IconPickerSheet` = a `LazyVGrid` of tappable icons. Store `routine.iconName: String`. Render with `Image(systemName:)` everywhere a routine appears. |

---

## 2. Workout runner

`SessionFocusView.swift` logs sets, has a rest timer and a plate-math sheet. Missing:

### 2.1 RIR / RPE column in the set table

| | |
|---|---|
| **What it does** | A third stepper column next to weight and reps: rate how close to failure the set was, on the athlete's chosen scale (RIR counts reps left, RPE reads 6–10). Opt-in (Settings → Effort per set). Empty ≠ 0. |
| **Status** | Missing from the runner. Engine ready: `LoggedSetSnapshot.rir` / `.effortRIR` exist; `EffortAnalyticsEngine` reads them. |
| **openGym ref** | `views/Workout.jsx` — the `ExerciseBlock` set-row grid, the `col2`/effort column and `stepEffort` from `lib/history.js` (`EFFORT`, `stepEffort`, `capEffort`). |
| **How to add** | In the set row of `SessionFocusView`, when `@AppStorage("gym_effort_mode") != "none"`, add a third `GymStepper`. Bind to a `Double?` on the row's working model; step 0.5; RIR range 0–10, RPE 6–10; a `−` on an empty cell leaves it empty, `+` from empty starts at the scale floor; stepping below the floor clears it. On `markDone`, write `set.rir` (RIR mode) or `set.rpe` (RPE mode) — never both. Column header shows "RIR" or "RPE". |

### 2.2 "Make superset with next"

| | |
|---|---|
| **What it does** | An inline button on the current exercise that links it with the next one into a superset — you then log them back-to-back with a rest only after the pair. |
| **Status** | Missing. `SupersetFlow` (grouping, `restSeconds` = longest member, `step`) is ported but not driven from the runner. |
| **openGym ref** | `views/Workout.jsx` — the "Make superset with next" button and `onPairNext`; `lib/supersetFlow.js`. |
| **How to add** | A `Button("Make superset with next", systemImage: "link")` under the exercise name, shown when there is a next entry not already grouped. It sets a shared `supersetID` on the two runner entries and persists. The rest/advance logic on set completion already flows through `SupersetFlow.step` / `restSeconds` / `restAfterSet` once you wire §2.9. |

### 2.3 Prev / Next nav + progress bar + "Exercise i / n"

| | |
|---|---|
| **What it does** | A top bar with a progress bar and "Exercise 3 / 6", and bottom **◀ Prev / Next ▶** to move between exercises without opening the list. |
| **Status** | Missing (you navigate via the list sheet only). |
| **openGym ref** | `views/Workout.jsx` — the header progress bar + "Exercise {i} / {n}" and the bottom `Prev`/`Next` buttons around the rest-timer control. |
| **How to add** | Add a `ProgressView(value: setsDone, total: setsTotal)` + `Text("Exercise \(idx+1) / \(count)")` to `SessionFocusView`'s top. Bottom bar: `Button` "Prev"/"Next" that change `runner.currentEntryIndex` (clamped), disabled at the ends. Keep the existing "open list" affordance. |

### 2.4 Warm-up rows / "Add warm-up set"

| | |
|---|---|
| **What it does** | Warm-up sets shown above the work sets, visually distinct, excluded from `ok`/PRs/volume; an "Add warm-up set" action; when a prescription changes the work weight, the warm-up ladder re-ramps toward it. |
| **Status** | Missing in the UI. Engine ready: `LoggedSetSnapshot.isWarmup`, `WarmupRamp.reramp`, `SessionReading` already filters warm-ups. |
| **openGym ref** | `views/Workout.jsx` — "Add warm-up set" / "Remove set"; `lib/history.js` — `insertWarmupRow`, `rerampWarmups`, `MAX_PLANNED_WARMUPS`. |
| **How to add** | Render rows with `set.isWarmup == true` in a lighter style with a "W" marker, above the work rows. "Add warm-up set" prepends a warm-up row (cap 5) seeded by `WarmupRamp.reramp` from the first work row's weight. Exclude warm-ups from the "sets done" counters. After `SessionEntryBuilder` applies a prescription, call `WarmupRamp.reramp` so the ladder tracks today's work weight. |

### 2.5 "Last time (date): 92.5×8 (RIR 3), …" recap

| | |
|---|---|
| **What it does** | Under the exercise name, a one-line recap of the most recent logged session for this exercise — each set's weight×reps and effort. |
| **Status** | Missing. |
| **openGym ref** | `views/Workout.jsx` — the "Last time (...)" line; built from `lastEntryFor` in `lib/history.js`. |
| **How to add** | A helper `lastPerformanceLine(exerciseID:sessions:unit:) -> String?` in `FitnessCore` (walk sessions newest-first, first entry with a done work set, format `w×r (RIR x)` joined by ", "). Render it as a dim caption in `SessionFocusView`. |

### 2.6 The "why" line on the logging screen

| | |
|---|---|
| **What it does** | The progression rationale ("Missed reps 3 sessions running — reset to 82.5 kg and work back up.") shown in the runner where you see the numbers, not just computed. |
| **Status** | Missing on screen. `Prescription.why` + `WhyTemplate.render()` exist and `SessionEntryBuilder` carries the `Prescription` on each built entry. |
| **openGym ref** | `views/Workout.jsx` — the yellow "why" line above the set table; `nextPrescription().why` in `lib/progression.js`. |
| **How to add** | In `SessionFocusView`, if the entry's `prescription.kind != .off/.first`, show `prescription.why.render()` in an accent-tinted row (yellow for deload, green for up) above the set table. |

### 2.7 Working-weight confirm ("{exercise} done")

| | |
|---|---|
| **What it does** | When an exercise's sets are all done, a small sheet asks you to confirm the working weight you actually used; the highest becomes next session's default; if it's a superset, it prompts for the partner too; "new record!" if it beats the prior best. |
| **Status** | Missing. |
| **openGym ref** | `sheets.jsx` → `topWeightSheet` / `TopWeight`; the `exWeights` map in `lib/history.js` / `useStore.js`. |
| **How to add** | A `WorkingWeightSheet` presented when `SessionRunner` detects a unit just finished. A `NumberField` pre-filled with `max(maxDoneSetWeight, storedWorkingWeight)`; "Save" writes `exWeights[exerciseID] = { kg, date }` (§7.1) and, for a multi-member superset, chains to the next member; a "new record" note when it beats `bestWeightFor`. Feeds `SessionEntryBuilder`'s seeding next time. |

### 2.8 Workout-complete prompt

| | |
|---|---|
| **What it does** | When the last set of the last exercise is checked, a centred prompt: "That's the whole workout! — Finish, or keep going and add another exercise." |
| **Status** | Partial — you have a finish flow but not the explicit "keep going" branch. |
| **openGym ref** | `sheets.jsx` → `workoutCompleteSheet` / `WorkoutComplete`. |
| **How to add** | When `SupersetFlow.nextUnfinishedUnit` returns nil after a set completion, present a `confirmationDialog` / centre sheet with "Finish workout" (→ summary) and "Continue" (dismiss; user can add an exercise). |

### 2.9 Rest/advance wiring (drives 2.2, 2.4, 2.8)

| | |
|---|---|
| **What it does** | On a set completion: a rest fires after **every** set except the last of the last unit; unchecking then re-checking a set does **not** replay navigation/rest/sheets; a superset unit rests once per round on its longest member's rest; per-exercise `restSec` overrides the global default. |
| **Status** | Helpers ported (`SupersetFlow.restAfterSet` / `restOnRecheck` / `restSeconds` / `step` / `progress`), not wired into `SessionRunner`/`SessionFocusView`. |
| **openGym ref** | `views/Workout.jsx` — the `toggle` handler and its `setProgressHighWater` / `restAfterSet` / `restSecFor` / `supersetFlowStep` calls; `lib/supersetFlow.js` JSDoc for the uneven-round and re-check rules. |
| **How to add** | In `SessionRunner`, keep `previousHighWater[entryIndex]`. On toggle→done: `SupersetFlow.progress` — if `isNew`, then if `restAfterSet(unitDone:lastUnit:)` start `WorkoutTimers` rest for `SupersetFlow.restSeconds(...)`; advance `currentEntryIndex` via `step` / `nextUnfinishedUnit`; if none left, present §2.8. On toggle→undone: no side effects. On re-check of a done set: `restOnRecheck(timerRunning:...)`. Add a per-entry `restSec: Int?` from the routine config (persist on `CompletedEntryModel`). |

### 2.10 Swap exercise mid-workout

| | |
|---|---|
| **What it does** | Replace an exercise during a session. Unlogged → replace in place (keeps notes, feel, superset membership). Logged → confirm, then insert the replacement beside the original (never relabel logged work); for a grouped member, ask keep-in-group or detach. |
| **Status** | Missing. `ActiveWorkoutEdits.swap` is ported. |
| **openGym ref** | `sheets.jsx` → `swapActiveWorkoutExercise`; `lib/active-exercise-swap.js`. |
| **How to add** | A "Swap exercise" `Button` in `SessionFocusView` → `ExercisePickerSheet` → `ActiveWorkoutEdits.swap(entries:index:replacement:loggedConfirmed:groupDisposition:)`; when it returns `.needsConfirmation`, show a `confirmationDialog`; then re-number `performedOrder` and persist. |

### 2.11 Notes — exercise (with pin) + session

| | |
|---|---|
| **What it does** | Three note lines per exercise (routine instruction / a **standing pinned** note that reappears next time / today's note), plus one overall session note. `NOTE_MAX` 500. |
| **Status** | Files `ExerciseNoteSheet.swift` / `SessionNoteSheet.swift` exist but aren't wired; `Notes` helper (`standing`, `pinned`, `clamp`) ported; `CompletedEntrySnapshot.note` / `.notePin` exist. |
| **openGym ref** | `views/Workout.jsx` — the `exnote` lines + the header pencil button; `sheets.jsx` → `exerciseNoteSheet`, `sessionNoteSheet`; `lib/history.js` → `pinnedNoteFor`, `NOTE_MAX`; `lib/finish-workout.js` — how `note`/`notePin` are written. |
| **How to add** | In `SessionFocusView`, show up to three caption rows per exercise: `config.coachNote` (from the routine), `Notes.pinned(exerciseID:sessions:)` ("From 15 Aug: …", highlighted, only while the exercise has work left), and the entry's own `note`. A pencil button in the exercise header opens `ExerciseNoteSheet` (a `TextEditor`, `Notes.clamp`, and a "Show this again next time" toggle → `entry.notePin`). A "Session note" button by the finish action opens `SessionNoteSheet` → `session.overallNote`. |

### 2.12 Drop-set / rest-pause sub-rows

| | |
|---|---|
| **What it does** | A set row can expand into weight-drop entries or short-rest bursts, logged on the same card. Drop volume adds to totals only (not 1RM/progression); a rest-pause row's own reps already include the bursts. Suggested next drop = −20 %; next burst ≈ half. |
| **Status** | `DropSetRow.swift` / `RestPauseRow.swift` exist; `SetRowOps` ported; `LoggedSetSnapshot.drops` / `.clusters` / `.extraDropVolumeKg` exist. Not wired. |
| **openGym ref** | `views/Workout.jsx` — the `.subrow` blocks; `lib/workout-model.js` — `addDrop`/`addCluster`, `nextDropWeight`, `nextBurstReps`, `splitBurstReps`, `extraVolumeOf`. |
| **How to add** | In the set row, a disclosure that reveals `DropSetRow` / `RestPauseRow` stacks with `+ drop` / `+ burst` buttons seeded by `SetRowOps.nextDropLoad` / `nextBurstReps`. Persist `drops`/`clusters` on `LoggedSetModel` (mapping already models them). Volume charts add `set.extraDropVolumeKg`; PR/1RM code keeps reading only the row's own `w`/`r`. |

### 2.13 Expand exercise media

| | |
|---|---|
| **What it does** | The exercise image/animation with an "Expand" control to view it large. |
| **Status** | Partial — you show a thumbnail. |
| **openGym ref** | `views/Workout.jsx` — the media card + "Expand"; `components/Media.jsx`. |
| **How to add** | Wrap `ExerciseMediaView` in a `Button` that presents a full-screen `.sheet` with the image zoomable (`.scaledToFit()` + magnification gesture). (Your dataset is static images — no GIF decoding needed.) |

---

## 3. Stats

`StatsView.swift` has tiles, the heatmap (just fixed), a muscle segmented control, and an
effort card. Missing:

### 3.1 Body-weight card on Stats

| | |
|---|---|
| **What it does** | The same body-weight card as Home, on Stats too, with 1M / 3M / 1Y / All windows. |
| **Status** | Home-only. |
| **openGym ref** | `views/Stats.jsx` — the "Body weight" `card` with the `Segmented` window and `LineChart points={bwPts} goal={S.targetW}`. |
| **How to add** | Extract Home's body-weight card into `Features/Common/BodyWeightCard.swift` (params: entries, target, window binding). Use it on both Home and Stats. Add a window `Picker` [1M/3M/1Y/All] filtering the points. |

### 3.2 Exercise progress card

| | |
|---|---|
| **What it does** | Pick any exercise (searchable), then a segmented **[Top set | Est. 1RM | Effort]** curve; a caption ("Best set weight per workout · Best: 152.5 kg"); for Est. 1RM, "Best estimate from 100 kg × 10 on 15 Aug — an estimate, not a tested max"; the fuller-dot effort note. Empty → "Finish your first workout to see progress curves here." |
| **Status** | Partial — you have an exercise curve with a metric-mode selector but it renders **fake data** when empty (fixed today to an empty state) and lacks the searchable picker + the "Best estimate from …" source line. |
| **openGym ref** | `views/Stats.jsx` — the "Exercise progress" `card`: the `SelectRow` exercise picker with search, the `Segmented` [Top set / Est. 1RM / Effort], and the caption lines including `e1Best`. |
| **How to add** | Add a searchable `ExercisePickerSheet` trigger (reuse §1.1's picker). Feed the chart from `Estimated1RM.series(exerciseID:sessions:formula:)` (Est. 1RM), a top-set series, or `EffortAnalyticsEngine.computeExercisePerformances` (Effort, inverted axis). Show `Estimated1RM.best(...)` → "Best estimate from {w}×{r} on {date}". |

### 3.3 "Where the sets land" — effort histogram

| | |
|---|---|
| **What it does** | A bar chart of rated sets bucketed 0 / 1 / 2 / 3 / 4+ RIR, with a caption about not living at failure. Answers "am I training too far from failure, or leaving nothing in the tank" — which an average hides. |
| **Status** | Missing. `EffortAnalyticsEngine.computeHistogram` returns the bins. |
| **openGym ref** | `views/Stats.jsx` — the "Where the sets land" block in `EffortCard`; `lib/effort.js` → `effortHistogram`. |
| **How to add** | Under the effort card's weekly chart, a horizontal bar row per `EffortHistogramBin` (bar width = `bin.percentage`, label `bin.label`, count). Only when `ratedSets >= MIN_RATED`. |

### 3.4 Fatigue / Strength body-map modes + legends

| | |
|---|---|
| **What it does** | The muscle segmented control has three modes: **Muscle balance** (effective sets, with an All/Hard toggle), **Fatigue** (how recently trained, red→yellow, legend "Fatigued / Recovering / Ready", caption "high means rest"), **Strength** (retained strength, own legend + caption, plus an "Exercises · {muscle}" list with Est. 1RM + date). |
| **Status** | Partial — you have the segmented control and a body map, but Fatigue/Strength likely aren't fed from `RecoveryModel` and lack the legends/captions. |
| **openGym ref** | `views/Stats.jsx` — `MuscleCard`: the `Segmented` [balance/fatigue/strength], the three `BodyMap` variants with `FATIGUE_LEVELS` / `STRENGTH_LEVELS`, `FatigueLegend` / `StrengthLegend`, and the per-muscle exercise list. |
| **How to add** | Feed the shared `MuscleMapView` three different `[MuscleGroup: Double]` maps: effective-set load (balance), `RecoveryModel.fatigueByMuscle(...)` (fatigue, thresholds → 4 levels), `RecoveryModel.retainedStrengthByMuscle(...)` (strength). Add a `FatigueLegend` / `StrengthLegend` small view and the mode caption. In Strength mode, when a muscle is selected, list its exercises with `Estimated1RM.best`. |

### 3.5 "Not trained in this period" + tap-muscle → exercises

| | |
|---|---|
| **What it does** | Under the balance map, a list of muscle groups that got zero (or zero hard) sets in the window; tapping any muscle on the map filters an exercise list to that muscle. |
| **Status** | Missing. |
| **openGym ref** | `views/Stats.jsx` — the "Not trained in this period" / "No hard sets in this period" section and the `onMuscle`/`sel` tap handling. |
| **How to add** | From the effective-set map, `MuscleGroup.allCases.filter { load[$0, default: 0] == 0 }` → a chip row. Make `MuscleMapView` report taps via a closure; hold `@State selectedMuscle`; show a filtered exercise list below. |

### 3.6 Recent workouts list

| | |
|---|---|
| **What it does** | The last few sessions as rows (date, name, sets, volume, PR count) with "All N →" to History; tapping a row opens the workout detail. |
| **Status** | Missing on Stats (you have `HistoryListView` as a separate screen). |
| **openGym ref** | `views/Stats.jsx` — the "Recent workouts" section + `WorkoutRow` + the "All {n}" button; `sheets.jsx` → `workoutDetailSheet`. |
| **How to add** | Reuse `HistoryListView`'s row as `WorkoutRow`; show `sessions.prefix(4)` on Stats with a `NavigationLink` to the full History; row tap → `WorkoutDetailSheet`. |

### 3.7 Heatmap tap → detail / calendar

| | |
|---|---|
| **What it does** | Tapping a heatmap cell opens that day's workout (if one) or the calendar at that day (if several / none). |
| **Status** | Missing (cells aren't tappable). |
| **openGym ref** | `views/Stats.jsx` — the `<Heatmap onDay={...}>` handler. |
| **How to add** | Give `ActivityHeatmapView` an `onDay: (Date) -> Void`; make each `dayCell` a `Button`. In `StatsView`, route to `WorkoutDetailSheet` or `CalendarSheet`. |

### 3.8 Effort card windows

Change the effort card window set from **Week / 30d / 90d / All** to **30d / 90d / 1Y / All**
(`rangePill` days: 30 / 90 / 365 / 0). Ref: `views/Stats.jsx` `EffortCard` `Segmented` options.

---

## 4. Settings

`SettingsView.swift` is large and close. Missing rows:

| Row | What | openGym ref | How to add |
|---|---|---|---|
| **Rest-pause rest** | Default short rest between rest-pause bursts (a `SelectRow` of seconds). | `views/Settings.jsx` "During a workout" → `Rest-pause rest` `SelectRow`. | `@AppStorage("gym_rest_pause_sec")` (you already have it) → surface a `Picker` [10/15/20/30 s]; `RestPauseRow` seeds new bursts from it. |
| **Exercise animations** | `[Full · Small · Hidden]` segmented — controls thumbnail size / whether media shows. | `views/Settings.jsx` → `Exercise animations` `Segmented` (`gifSize`). | `@AppStorage("gym_media_size")` [full/mini/off]; `ExerciseImageView` / `ExerciseMediaView` read it. |
| **Flash screen when timer ends** | Toggle: a four-pulse full-screen flash when the rest timer hits zero. | `views/Settings.jsx` → `Flash screen when timer ends` `Switch`; `components/TimerFlash.jsx`. | You have `@AppStorage("gym_timer_flash")`. Add a `TimerFlashOverlay` view (a white `Rectangle` that opacity-pulses ×4 on a trigger id) at the app root; `WorkoutTimers` bumps the id at zero when the flag is on. |
| **Import from Hevy (API key)** | Pull history via a Hevy Pro API key, not just CSV. | `views/Settings.jsx` → `Import from Hevy` row; `lib/import-hevy.js`, `lib/hevy-id-map.js`. | Lower priority (needs a network call + the id map). A `TextField` for the key → fetch Hevy's workout endpoint → map to your `CompletedSessionSnapshot` via an exercise-name/id matcher → merge. Ship CSV import first. |
| **Week starts on** | You have the `@AppStorage`; thread `WeekStart` into `StreakCalculator`, `WeekKey`, the heatmap grid, `CalendarSheet`, and Home's week strip. | `views/Settings.jsx` → `Week starts on` `Segmented`; `lib/week-start.js`. | Pass the setting to every `WeekKey.startOfWeek` / `computeSummary(weekStart:)` call site; order Home's strip and Plan's schedule by it. |

---

## 5. Home polish

| Item | What | openGym ref | How to add |
|---|---|---|---|
| **Week-strip dot states** | 4 dot styles: done (accent), planned (grey), rescheduled (distinct), today (ring). | `views/Home.jsx` — the `strip` build, `dot` class from `done / ovr && eff / eff`. | Per day compute `Scheduling.effectiveRoutineID`, `dayPlan[iso] != nil`, and whether a workout exists that day → pick the dot fill/stroke. |
| **TODAY row states** | The row switches: in-progress → orange "Resume"; done-today → "Done" / "Workout done"; rest day → **"Next session: Fri, Pull Day"**; rescheduled → "· rescheduled". | `views/Home.jsx` — the `today-row` block (`S.active` / `doneToday` / `routine` / `next` branches). | In `HomeView`, derive `active` (a `finishedAt == nil` session for today), `doneToday` (a finished one), the effective routine, and `Scheduling.nextTrainingDay`. Render the icon/title/tag accordingly. |
| **Empty-state card** | For a fresh user: "Welcome! — Load starter plan (PPL) / Build my own plan". | `views/Home.jsx` — the `!S.routines.length` card. | Show when there are no routines: two buttons — seed PPL, or push PlanView. |
| **Personalized header** | "Hi {name}" instead of a static title. | `views/Home.jsx` — `t('Hi {0}', user.name)`. | If you keep a profile name, use it; otherwise leave "PulseAI" — cosmetic. |

---

## 6. Backfill — log a past workout

| | |
|---|---|
| **What it does** | The same runner screen aimed at a past date: no rest timers, a "Logging a past workout" banner, filed into history in date order (optionally replacing an existing session that day). |
| **Status** | `BackfillOps` (`startInstant`, `endInstant`, `insertChronological`, `commit`) and `SessionEntryBuilder` are ported; `BackfillEntryView.swift` exists. Not wired. |
| **openGym ref** | `lib/backfill.js`; `lib/session-start.js` (`buildSessionEntries` — one path for live + backfill); `views/Workout.jsx` — the `A.backfill` branch (banner, no `startRest`). |
| **How to add** | Add a "＋ Log past workout" button on `HistoryListView` and on the calendar day sheet → `BackfillEntryView` (pick routine, date, duration, optional "replace that day's session") → construct the `SessionRunner` with a `BackfillContext`. In the runner: build entries via `SessionEntryBuilder`, stamp `startedAt`/`finishedAt` from `BackfillOps`, don't start `WorkoutTimers`, show the banner, and on finish call `BackfillOps.commit(sessions:session:replaceID:)` before PR/1RM detection. |

---

## 7. Cross-cutting

### 7.1 Data model additions

The persisted model needs these fields (keep names openGym-JSON-compatible where you can so
an openGym export imports):

| Concept | Where | Fields |
|---|---|---|
| **Routine** (editable) | new `@Model Routine` or a JSON blob on the plan | `id`, `name`, `iconName`, `policy: String?` (routine default), `excludeFromProgression: Bool`, `exercises: [ExerciseConfig]` (ordered) |
| **ExerciseConfig** | on `Routine` | `exerciseID`, `sets`, `reps`, `repsMin: Int?`, `repsMax: Int?`, `weightKg: Double`, `restSec: Int?`, `mode: String` (reps/time/cardio), `sec: Int`, `speed: Double`, `bodyweight: Bool`, `perSide: Bool`, `supersetID: String?`, `policy: String?` (override), `incKg: Double?`, `coachNote: String` |
| **Weekly schedule** | store / profile | `week: [Int: String]` (weekday → routineID), `dayPlan: [String: String]` (iso date → routineID \| "rest") |
| **Working weights** | store | `exWeights: [String: (kg: Double, date: Date)]` |
| **Bar weights** | store | `barWeights: [String: Double]` (per exercise, for plate math) |
| **Notes** | `CompletedEntryModel` / a standing map | entry `note`, `notePin: Bool`; `exNotes: [String: String]` standing per-exercise |
| **Set intensifiers** | `LoggedSetModel` | `rir: Double?`, `heldSec: Int?`, `isWarmup: Bool`, `drops: [DropSetEntry]`, `clusters: [RestPauseCluster]` (snapshot types already model these) |
| **Session flags** | `CompletedSessionModel` | `excludeFromProgression: Bool`, `overallNote: String?` |
| **Settings** | `@AppStorage` | `gym_week_start`, `gym_media_size`, `gym_rest_pause_sec` (exist), plus wire `gym_effort_mode` into the runner |

If routines currently only come from the AI `WeeklyPlan`: introduce a real `Routine` store,
seed it from the AI plan on first run, and let the AI regenerate *into* it (the AI writes
routines; the user edits them).

### 7.2 Components to add / extend

| Component | Status | Add |
|---|---|---|
| `MuscleMapView` | exists | fatigue & strength level modes; a tap closure; front+back + M/F already there |
| `FatigueLegend` / `StrengthLegend` | missing | small `HStack` of colour swatches + labels |
| `TimerFlashOverlay` | missing | root-level pulse overlay driven by a trigger id |
| `BodyWeightCard` | inline in Home | extract to a shared view, param window |
| `ExercisePickerSheet` | inline in Library | extract to reusable sheet (search + body-part + equipment filters) |
| `WorkoutRow` | inline in History | extract; reuse on Stats "Recent workouts" |
| `SegmentedControl` | ad hoc | a reusable pill segmented control matching `GymTheme` (used by Stats ×4, Settings ×5) |

### 7.3 Wiring checklist (existing `FitnessCore` helpers → views)

- `SessionReading` + `ProgressionRule.next(current:mechanic:history:)` → `SessionEntryBuilder` → `SessionRunner.start` (replace the current inline build). Surfaces §2.6 the "why" line.
- `SupersetFlow` → `SessionRunner` toggle handler (§2.9).
- `SetRowOps` → `DropSetRow` / `RestPauseRow` (§2.12).
- `ActiveWorkoutEdits` → `SessionFocusView` swap/reorder (§2.10).
- `Notes` → `ExerciseNoteSheet` / `SessionNoteSheet` / `SessionFocusView` caption rows (§2.11).
- `Scheduling` → `HomeView` TODAY row + week strip, `PlanView` schedule (§5, §1.3).
- `WeekKey` + `StreakCalculator(weekStart:)` → Home, Stats, heatmap, calendar (§4 week-start).
- `EffortAnalyticsEngine.computeHistogram` → §3.3; `computeExercisePerformances` → §3.2.
- `Estimated1RM.series/best/isRecord` → §3.2, finish summary.
- `RecoveryModel` → §3.4 fatigue/strength maps.
- `PlateMath.plateSplit` + `barWeights` → §7.1 bar weight sheet + `PlateMathSheet`.
- `BackfillOps` + `SessionEntryBuilder` → §6.

### 7.4 Suggested build order

1. **Data model** (§7.1) — the `Routine`/`ExerciseConfig` store + `week`/`dayPlan`/`exWeights`. Everything else needs it.
2. **RoutineEditView + ExerciseConfigSheet + PlanView rework** (§1) — unblocks real routines.
3. **Runner wiring** (§2.9, 2.1, 2.4, 2.5, 2.6, 2.7, 2.8) — the core loop.
4. **Runner extras** (§2.2, 2.10, 2.11, 2.12, 2.13).
5. **Stats** (§3).
6. **Settings + Home polish + week-start threading** (§4, §5).
7. **Backfill** (§6).
