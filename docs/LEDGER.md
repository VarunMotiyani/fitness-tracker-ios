# Architecture & Implementation Ledger

_Formal Engineering Ledger for `fitness-tracker-ios` (PulseAI)._  
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
│  │   ├── Split Routine Cards · Rest Day Indicators · Generator Modal   │
│  ├── WorkoutRunner (SessionFocusView, SetTable, RestTimer, Finalizer)  │
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
│  ├── ProgressionRule (Linear, Double Progression, Greyskull LP)        │
│  └── StreakCalculator (10-Year ISO Week Scanner, Adherence Counters)   │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Milestone Execution Ledger

### Milestone 1: Domain Core & Calculation Engine (`FitnessCore`)
- **Status:** **COMPLETE**
- **Test Suite:** **136/136 tests passing** across 12 suites (`swift test`).
- **Key Modules**:
  - `PlateMath.swift`: Computes exact barbell plate configurations for 20kg/45lb Olympic, 15kg/35lb Women's, 10kg/25lb EZ, 25kg/55lb Trap, and Smith machine bars.
  - `RecoveryModel.swift`: Exponential stimulus saturation, 36h fatigue decay half-life, and readiness state engine.
  - `ProgressionRule.swift`: Progression heuristics for linear progression, double progression, Greyskull LP, and deload cycles.
  - `StreakCalculator.swift`: ISO-8601 calendar week grouping, 520-week backward scanner with current-week grace period, and adherence rollups.

---

### Milestone 2: 5-Tab Navigation & Theme Tokens (`FitnessTracker`)
- **Status:** **COMPLETE**
- **Design Tokens (`Theme.swift`)**:
  - Pitch Black: `#000000`
  - Elevated Backdrop: `#0e0e10`
  - Card Surface: `#1c1c1e`
  - Control Surface: `#2c2c2e`
  - Dynamic Accents: Lime (`#30d158`), Cyan (`#0a84ff`), Orange (`#ff9f0a`), Violet (`#bf5af2`), Pink (`#ff375f`), Red (`#ff453a`), Teal (`#64d2ff`), Gold (`#ffd60a`).
- **Navigation (`CustomTabBar.swift` & `RootView.swift`)**:
  - 5-item bottom bar with floating elevated center green action button (`Start` / `Resume`).
  - **Inline Settings Navigation**: Settings is rendered directly within the RootView navigation hierarchy so the bottom tab bar is permanently visible.

---

### Milestone 3: PulseAI Home Dashboard & Snug Modal Sheets
- **Status:** **COMPLETE**
- **Components**:
  - `HomeView.swift`: Dynamic 7-day week strip with active day indicator, interactive day clicks opening `DayOverrideSheet`, nested Today routine card with Start tag, bodyweight card with 30-day bezier curve chart, and 1-week streak card.
  - `LogWeightSheet.swift`: Snug presentation height, `Recent weigh-ins` historical entries with delete trash buttons, weight stepper, delta pills, and dynamic slider track.
  - `DayOverrideSheet.swift`: Clean header spacing, split routine selection, rest day marking, and back to weekly plan.
  - `CalendarSheet.swift`: Month calendar grid with aggregate duration/tonnage rollups, trained day indicators, and legend. Snug height (`445pt` or `495pt`).
  - `TargetWeightSheet.swift`: Goal management modal (`320pt` / `380pt`).
  - `WorkoutDetailSheet.swift`: Per-exercise set breakdown and session notes.

---

### Milestone 4: 1,324 Exercise Database & High-Definition Media
- **Status:** **COMPLETE**
- **Components**:
  - `catalog.json`: 1,324 exercises mapped with primary/secondary muscle groups, equipment types, and multi-step instructions.
  - `FreeExerciseDBMapper.swift`: Normalizes raw exercise database structures into domain models.
  - `ExerciseMediaView.swift`: CDN image thumbnails with memory caching and hardware-accelerated animated GIFs.
  - `LibraryView.swift`: Subtitle count (`1324 exercises with animations`), custom exercise creator card, and dynamic batch pagination.
  - `ExerciseDetailSheet.swift`: Interactive modal displaying exercise demonstration media, muscle chips, equipment tags, and instructions.

---

### Milestone 5: Gym-Floor Workout Runner & Volume Analytics
- **Status:** **COMPLETE**
- **Components**:
  - `SessionFocusView.swift`: Tactile Set Table, weight/rep steppers, rest timer with sound/haptic cues, and session finalizer.
  - `StatsView.swift` & `MuscleMapView.swift`: Canvas vector body maps (Anterior / Posterior), 52-week activity heatmap, e1RM progression charts, and RIR effort analysis.
  - `SettingsView.swift`: AI Coach settings, Keychain store, Athlete profile, Appearance themes, and JSON export/import.

---

## 3. Verified Simulator State

- **Platform:** iOS Simulator (iPhone 17 Pro, iOS 26.5 / `B29C47DD-D3FE-490C-9A84-3D9A32AFE68A`).
- **Build Status:** Build Succeeded with 0 warnings/errors.
- **UI/UX Validation:** All sheets (`LogWeightSheet`, `CalendarSheet`, `DayOverrideSheet`, `TargetWeightSheet`) open snugly with zero wasted space, persistent bottom navigation, and dynamic theme accent coloring.

---

## 4. Next Priorities

1. **AI Proactive Coach Feedback**: Integrate completed workout volume and RIR trends into the prompt builder to provide automatic overload adjustments before each workout.
2. **HealthKit Bi-Directional Sync**: Sync bodyweight and completed workouts with Apple Health.
3. **Live Activity & Lock Screen Widgets**: Background workout timer with Dynamic Island support.
