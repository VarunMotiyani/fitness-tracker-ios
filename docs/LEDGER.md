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
│  │   ├── ExerciseSwapSheet · ActiveWorkoutEdits · WorkoutTimers        │
│  │   └── WorkoutTimers (Rest & Timed Work Countdowns), Notes Sheets    │
│  ├── HistoryView (BackfillEntryView, WorkoutDetailSheet, Calendar)     │
│  ├── StatsView (MuscleMapView Canvas, 52W Heatmap, e1RM, Effort RIR)   │
│  ├── LibraryView (1,324 Exercises, ExerciseThumbnailView, DetailSheet) │
│  └── SettingsView (Inline Navigation, BYOK AI, Theme Swatches, Backup) │
│      ├── EquipmentProfileSheet · HevyAPISyncSheet · HistoryExport      │
│      └── Multi-App CSV/XML Importer & SwiftData History Ingestion      │
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
│  ├── CSVParser & ExternalAppImporter (RFC 4180 CSV, Hevy, Strong, XML) │
│  └── Notes & Scheduling (Effective Routine, Next Training Day, Pins)   │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Milestone Execution Ledger

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

### Phase 4: Data Import/Export, Hevy REST Sync, Equipment Profiles & Exercise Swap
- **Status:** **100% COMPLETE & VERIFIED**
- **Key Modules & Features**:
  - **`CSVParser.swift` & `ExternalAppImporter.swift`**: Pure Swift RFC 4180 CSV parser and multi-format importer auto-detecting Hevy, Strong, FitNotes (iOS & Android) with unit conversion (lbs to kg), set categorization, and session grouping.
  - **`AppleHealthXMLImporter.swift`**: SAX streaming XML parser extracting Apple Health body mass records with lossless timestamps and values.
  - **`HevyAPIClient.swift` & `HevyAPISyncSheet.swift`**: Paged REST client for `api.hevyapp.com/v1/` (`exercise_templates`, `workouts`, `body_measurements`) with 429 rate-limit backoff, live UI sync progress bar, and instant SwiftData ingestion.
  - **`HistoryIngestionService.swift`**: SwiftData service mapping external sessions and bodyweight into `CompletedSessionModel`, `CompletedEntryModel`, `LoggedSetModel`, and `BodyweightEntryModel`.
  - **`EquipmentModels.swift` & `EquipmentProfileSheet.swift`**: Equipment profile manager supporting named custom equipment environments (Commercial Gym, Home Dumbbells, Travel Hotel) and library filtering.
  - **`HistoryExportManager.swift`**: Complete RFC 4180 CSV export of workout logs and full JSON backup exporter.
  - **`ExerciseSwapSheet.swift` & `SessionRunner.swapExercise`**: Mid-session exercise swap sheet with primary muscle filtering, search, and in-place / next-entry replacement.

---

## 3. Test Verification Matrix

| Suite | Tests Count | Status | Duration |
| :--- | :--- | :--- | :--- |
| **FitnessCore Unit Tests** | **195 Tests (26 Suites)** | **100% PASS** | 0.007s |
| **FitnessTracker App Tests** | **63 Tests (16 Suites)** | **100% PASS** | 1.2s |
| **FitnessTracker UI Tests** | **Automated UI Suite** | **100% PASS** | 15.9s |
| **Total Automated Tests** | **258 Tests** | **100% PASS** | — |

---

## 4. Live Simulator Verification

- **Simulator Target:** iPhone 17 Pro (iOS 26.5 / `B29C47DD-D3FE-490C-9A84-3D9A32AFE68A`).
- **Verified Screens**:
  1. **Home Screen (`audit_ui_home.png`)**: PulseAI branding, outline gear icon, 7-day week strip with 4-state status dots, chronologically sorted bodyweight 30-day curve, streak card.
  2. **Workout Tab (`audit_ui_workout_tab.png`)**: Energy selector, time available pills, Start workout FAB.
  3. **Workout Runner (`audit_ui_session_runner.png`)**: Top header with ✕ close, live elapsed timer, total-set progress bar, exercise media stage with expand pill, meta chips, last-time recap, rationale banner, all-sets editable table, and inline set actions.
  4. **Settings Screen (`audit_ui_settings_top.png`, `audit_ui_settings_middle.png`, `audit_ui_settings_bottom.png`)**: Effort per set, Keep screen awake, Timer flash overlay, Theme swatches, Equipment profile link, and Data Management.
  5. **Equipment Profiles Sheet (`audit_ui_equipment_profiles.png`)**: Commercial Gym, Home Dumbbells, Travel Hotel presets, active status pill, and "+ Add equipment profile".

---

## 5. Next Steps for Development

1. **Live Activity & Lock Screen Dynamic Island**: Background rest timer countdown and live workout tracking for Dynamic Island.
2. **HealthKit Bi-Directional Sync**: Sync bodyweight and completed workouts with Apple Health.
3. **Audio / Voice Coaching**: Spoken rest countdown and set completion cues.
