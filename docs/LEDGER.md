# Architecture & Implementation Ledger

_Formal Engineering Ledger for `fitness-tracker-ios` (PulseAI - Proactive AI Strength & Physique Coach)._  
_Current Branch: `fitness-engine-v2` | Target: iPhone (iOS 17+) / Swift 6 Strict Concurrency_

---

## 1. System Architecture Overview

```
┌────────────────────────────────────────────────────────────────────────┐
│                        SwiftUI Presentation Layer                      │
│  RootView (5-Tab Coordinator) · CustomTabBar · GymTheme (Pure Black)   │
│  ├── HomeView (Week Strip, Bodyweight Card + Chart, Streak Card)       │
│  │   ├── CalendarSheet · DayOverrideSheet · WorkoutDetailSheet         │
│  │   └── LogWeightSheet · TargetWeightSheet · WeightInputView          │
│  ├── PlanView (Microcycle Schedule, Routine Breakdown, RP Targets)     │
│  │   ├── RoutineEditView · DayAssignSheet · ExerciseConfigSheet        │
│  │   └── IconPickerSheet · PlanShareSheet (JSON / PDF)                 │
│  ├── WorkoutRunner (SessionFocusView, All-Sets Table, Steppers)        │
│  │   ├── ExerciseMediaZoomSheet · WorkingWeightSheet · TimerFlash      │
│  │   └── WorkoutTimers (Rest & Timed Work Countdowns), Notes Sheets    │
│  ├── HistoryView (BackfillEntryView, WorkoutDetailSheet, Calendar)     │
│  ├── StatsView (MuscleMapView Canvas, 52W Heatmap, e1RM, Effort RIR)   │
│  ├── LibraryView (1,324 Exercises, ExerciseThumbnailView, DetailSheet) │
│  └── SettingsView (Inline Navigation, BYOK AI, Theme Swatches, Backup) │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│                  Autonomous AI Coaching & BYOK Layer                   │
│  LLMProviderFactory · GeminiProvider · OpenAICompatibleProvider        │
│  KeychainStore · PlanCoordinator · PlanPromptBuilder · CostSummary     │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│                    Persistence Layer (SwiftData)                       │
│  UserProfile · StoredPlan · CompletedSessionModel · LoggedSetModel     │
│  BodyweightEntryModel · PersonalRecordModel · ProviderProfile          │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│                  Domain Core Engine (`FitnessCore`)                    │
│  FitnessDomain · ExerciseCatalog (1,324 Exercises) · Metrics           │
│  ├── PlateMath (Olympic, EZ, Trap, Smith Plate Calculator)             │
│  ├── RecoveryModel (Fatigue Half-Life Decay, Saturation Curve)         │
│  ├── ProgressionRule (Linear, Double Progression, Greyskull LP, AMRAP) │
│  ├── StreakCalculator & WeekKey (ISO & Sunday Week Starts, 10-Yr Scan) │
│  ├── EffortAnalyticsEngine (5-Rated Set Threshold, Weekly Trends, Hist)│
│  ├── Estimated1RM (Epley, Brzycki, Lombardi with Rep Cap 12)           │
│  ├── SupersetFlow (Units, Contiguous Reorder, Rest Engine)             │
│  ├── SetRowOps (Drop Sets, Rest-Pause Clusters, Volume Calculation)    │
│  ├── SessionEntryBuilder & BackfillOps (Chronological Insert & Replace)│
│  └── Notes & Scheduling (Effective Routine, Next Training Day, Pins)   │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Milestone Execution Ledger

### Phase 3a: Progression Parity Engine (`FitnessCore`)
- **Status:** **100% COMPLETE & VERIFIED**
- **Test Suite:** 191/191 tests passing in `FitnessCore`.
- **Key Modules**:
  - `SessionReading.swift`: `PrescriptionTarget`, weight accessors, and history aggregation.
  - `RepRangeNormalize.swift`: `normalize(reps:stride:)` with explicit parsing, stride-2 alignment, and inversions.
  - `WarmupRamp.swift`: `WarmupRampCalculator.ramp(workWeightKg:barWeightKg:equipment:)` with non-monotone pruning and ascending ladder generation.
  - `ProgressionRule.swift`: Full progression parity across linear progression (3 misses before deload), double progression (rep ceiling climb then reset), Greyskull LP (AMRAP doubling double-jump), time progression, bodyweight progression, and deload policies.

---

### Phase 3b: Metrics, Recovery, Effort Analytics & PlateMath Parity
- **Status:** **100% COMPLETE & VERIFIED**
- **Key Modules**:
  - `MetricSnapshots.swift`: Normalized `effortRIR` (`rir ?? (10 - rpe)`), lossless mapping for `heldSec` and `rir`.
  - `Estimated1RM.swift`: Epley, Brzycki, Lombardi 1RM calculation capped at 12 reps, `series`, `best`, and `isRecord`.
  - `EffortAnalyticsEngine.swift`: 5-rated set minimum floor for summary statistics, weekly drop-below-2 rated sets filter, and hard set histogram (RIR 0..3 vs 4+).
  - `PlateMath.swift`: Bar weight resolution (`usesBar`, `barWeightFor`), plate split math, and Olympic/EZ/Smith barbell support.

---

### Phase 3c: Session Runner, Superset Flow & Intensifiers
- **Status:** **100% COMPLETE & VERIFIED**
- **Key Modules**:
  - `SupersetFlow.swift`: Pure engine grouping consecutive entries into superset units, cycling step order, calculating longest member rest, and enforcing rest after every set except the workout's final set.
  - `SetRowOps.swift`: Drop-set and rest-pause cluster management (`addDrop`, `addCluster`, `nextDropLoad`, `splitBurstReps`, `extraVolume`).
  - `ActiveWorkoutEdits.swift`: Mid-workout reorder unit preserving superset contiguity, unlogged swap in-place, and logged-safe confirmation/insertion.
  - `WorkoutTimers.swift`: `@MainActor @Observable` state machine managing rest and work countdowns, local sound cues, haptics, and background notifications.
  - `DropSetRow.swift` & `RestPauseRow.swift`: Interactive drop-set (-20% load) and rest-pause (15s cluster burst) UI components.

---

### Phase 3d: Backfill & Shared Session Start
- **Status:** **100% COMPLETE & VERIFIED**
- **Key Modules**:
  - `SessionEntryBuilder.swift`: Single code path for live starts and past workout logging.
  - `BackfillOps.swift`: `startInstant`, `endInstant`, chronological insertion, and replacement of previous sessions.
  - `BackfillEntryView.swift`: Dedicated past workout logging interface with routine picker, date/time selector, and duration stepper.

---

### Phase 3e: Notes & Scheduling
- **Status:** **100% COMPLETE & VERIFIED**
- **Key Modules**:
  - `WeekKey.swift` & `StreakCalculator.swift`: Configurable `weekStart` (`.monday` / `.sunday`), single source of truth for streaks across Home and Stats.
  - `Scheduling.swift`: `effectiveRoutineID(week:dayPlan:date:)` and `nextTrainingDay(from:)`.
  - `Notes.swift`: Standing per-exercise note, pinned note extraction, and length clamping (`NOTE_MAX = 500`).
  - `ExerciseNoteSheet.swift` & `SessionNoteSheet.swift`: 3-tier exercise note viewer/editor and overall session reflection editor.

---

### Phase 3f: UI Fixes & Comprehensive Verification
- **Status:** **100% COMPLETE & VERIFIED**
- **Key Modules**:
  - `HomeView.swift`: Switched to single-source `StreakCalculator.computeSummary`, updated branding to **PulseAI**, fixed date alignment.
  - `ActivityHeatmapView.swift`: Fixed week-start 52-week column alignment and relative day shading by duration/volume.
  - `Theme.swift`: Standardized color tokens and active theme accents.

---

### Phase 3g: openGym vs PulseAI Full Screen Diff & UI/Behavioral Parity
- **Status:** **100% COMPLETE & VERIFIED**
- **Key Modules & Features**:
  - **`HomeView.swift`**: Outline `gearshape` in circular badge, ascending chronological sorting for bodyweight chart, 4-state session status dots (Green, Orange, Gray, Clear), dynamic TODAY card with `COMPLETED TODAY` / `TODAY` states.
  - **`PlanView.swift`**: 34pt bold title + subtitle, individual rounded cards per weekday with 8pt gap, sentence-case section headers, green-tinted `+ New` routine pill.
  - **`RoutineModels.swift`**: `RoutineDraft`, `ExerciseConfig`, `StarterRoutines.ppl()`.
  - **`RoutineEditView.swift`, `DayAssignSheet.swift`, `ExerciseConfigSheet.swift`, `IconPickerSheet.swift`, `PlanShareSheet.swift`**: Full routine builder suite with SF Symbol icon picker, drag-and-drop exercise reordering, per-exercise configuration (reps/time/cardio), and JSON import/export.
  - **`SessionFocusView.swift`**: Top session header with `✕` close, live elapsed timer `mm:ss`, pinned sets progress bar `0/12 sets`, and `✓` finish button; clean media stage with `⤢ Expand` pill opening `ExerciseMediaZoomSheet.swift`; bold exercise header + `ⓘ` info sheet + meta chips (`[Chest]` `[Barbell]` `[Best: 85.0 kg]`); "Last time" recap line; autoregulation rationale banner; "Make superset with next" button; **All-Sets Editable Table** with inline `[− weight +] [− reps +] [− RIR +]` steppers and `○` check circle; inline `🔥 Add warm-up set`, `− Remove set`, `+ Add set` actions; and post-exercise `WorkingWeightSheet.swift`.
  - **`GymStepper.swift` & `EffortStepper.swift`**: Compact single-line gym floor steppers with haptics.
  - **`ActivityHeatmapView.swift`**: 5-level intensity gradient scale with "Less time / More time" legend.
  - **`CustomTabBar.swift`**: `dumbbell.fill` FAB icon, `list.bullet` Exercises icon.

---

## 3. Test Verification Matrix

| Suite | Tests Count | Status | Duration |
| :--- | :--- | :--- | :--- |
| **FitnessCore Unit Tests** | **191 Tests (25 Suites)** | **100% PASS** | 0.006s |
| **FitnessTracker App Tests** | **59 Tests (13 Suites)** | **100% PASS** | 0.77s |
| **Total Automated Tests** | **250 Tests** | **100% PASS** | — |

---

## 4. Live Simulator Verification

- **Simulator Target:** iPhone 17 Pro (iOS 26.5 / `B29C47DD-D3FE-490C-9A84-3D9A32AFE68A`).
- **Verified Screens**:
  1. **Home Screen (`audit_screen_diff_home.png`)**: PulseAI branding, outline gear icon, 7-day week strip with 4-state status dots, chronologically sorted bodyweight 30-day curve, streak card.
  2. **Plan Screen (`audit_screen_diff_plan.png`)**: 34pt Plan header, sentence-case sections, individual weekday cards, routine cards, and `+ New` pill.
  3. **Workout Runner (`audit_screen_diff_workout_runner.png`)**: Top header with ✕ close, live elapsed timer, total-set progress bar, exercise media stage with expand pill, meta chips, last-time recap, rationale banner, all-sets editable table, and inline set actions.
  4. **Logged Workout (`audit_workout_logged_set.png`)**: Interactive set logging with haptic feedback, real-time sets done update, and rest timer triggering.

---

## 5. Next Steps for Development

1. **Live Activity & Lock Screen Dynamic Island**: Background rest timer countdown and live workout tracking.
2. **HealthKit Bi-Directional Sync**: Sync bodyweight and completed workouts with Apple Health.
3. **Audio / Voice Coaching**: Spoken rest countdown and set completion cues.
