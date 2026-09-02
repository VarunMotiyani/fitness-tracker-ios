# Architecture & Implementation Ledger

_Formal Engineering Ledger for `fitness-tracker-ios`._  
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
│  ├── WorkoutRunner (SessionFocusView, SetTable, RestTimer, Finalizer)  │
│  ├── StatsView (MuscleMapView Canvas, 52W Heatmap, e1RM, Effort RIR)   │
│  ├── LibraryView (1,324 Exercises, ExerciseThumbnailView, DetailSheet) │
│  └── SettingsView (AI Providers, Keychain, Unit/Rest/Awake, Export)    │
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
  - Brand Green: `#30d158`
  - Accent Amber/Orange: `#ff9f0a`
  - Accent Yellow: `#ffd60a`
  - Accent Blue: `#0a84ff`
  - Accent Purple: `#bf5af2`
- **Navigation (`CustomTabBar.swift` & `RootView.swift`)**:
  - 5-item bottom bar with floating elevated center green action button (`Start` / `Resume`).

---

### Milestone 3: Home Dashboard & Modal Flows
- **Status:** **COMPLETE**
- **Components**:
  - `HomeView.swift`: Dynamic 7-day week strip with active day indicator, nested Today routine card with Start tag.
  - `OpenGymLineChart.swift`: Hand-rolled bezier curve with vertical gradient fill, dashed goal line, and value endpoints.
  - `WeightInputView.swift`: Stepper buttons, delta pills (`[ −1 ]`, `[ −0.5 ]`, `[ +0.5 ]`, `[ +1 ]`), and continuous slider.
  - `LogWeightSheet.swift` & `TargetWeightSheet.swift`: Bodyweight logging with SwiftData persistence and goal target management.
  - `CalendarSheet.swift`: Month calendar grid with aggregate duration/tonnage rollups, trained day indicators, and legend.
  - `DayOverrideSheet.swift`: Day rescheduling and rest day marking.
  - `WorkoutDetailSheet.swift`: Per-exercise set breakdown and session notes.

---

### Milestone 4: 1,324 Exercise Database & High-Definition Media
- **Status:** **COMPLETE**
- **Components**:
  - `catalog.json`: 1,324 exercises mapped with primary/secondary muscle groups, equipment types, and multi-step instructions.
  - `FreeExerciseDBMapper.swift`: Normalizes raw exercise database structures into domain models.
  - `ExerciseMediaView.swift`:
    - `ExerciseThumbnailView`: CDN-cached visual image loader with smooth placeholder fallbacks.
    - `AnimatedGifView`: Hardware-accelerated inline GIF player with `GIF / Still` toggle.
  - `ExerciseDetailSheet.swift`: Interactive modal displaying exercise demonstration media, muscle chips, equipment tags, and instructions.

---

### Milestone 5: Unified Settings & AI Intelligence Suite
- **Status:** **COMPLETE**
- **Components (`SettingsView.swift`)**:
  - Local-first privacy architecture: SwiftData on-device storage.
  - AI Providers: Multi-provider manager (OpenAI, Gemini, Ollama, Anthropic) with Keychain security and real-time cost tracking.
  - Preferences: Unit selector (`kg`/`lb`), Week start day (`Monday`/`Sunday`), Rest timer presets, Screen awake toggle (`UIApplication.shared.isIdleTimerDisabled`), Sound/haptics, Timer flash, Effort mode (`RIR`/`RPE`) with Effort Scale Help Sheet.
  - Appearance: Male/Female diagram model, Accent color palette.
  - Data Management: Load starter plan, Export JSON backup via iOS Share Sheet, Database reset.

---

## 3. Working Guidelines & Quality Invariants

1. **Strict Git Discipline**: No `git commit` or `git push` without explicit user request.
2. **Swift 6 Concurrency**: Clean isolation boundaries with `@MainActor` UI and `nonisolated` pure domain calculation routines.
3. **No External Charting Dependencies**: Pure SwiftUI Canvas and Path graphics for high-performance zero-dependency rendering.
4. **Local-First & Offline Capable**: Fully functional without network access, using local rule engines and cached catalogs.
