# HANDOFF — Read This First

_Living document. Last updated: 2026-09-03 (openGym Full Architecture & UI/UX Port Completed on branch `fitness-engine-v2`)._

**Purpose:** One read = full context. If you're a new agent/session on any device, read this top to bottom before doing anything. It captures the project, every decision, current state, how to work here, and what's next. Deep detail lives in the numbered docs; this is the index + digest.

---

## 1. What the project is

A **personal iOS app** for Varun (24) that acts as an adaptive strength & physique coach, matching the exact UI/UX, floor mechanics, and domain architecture of **openGym** while integrating an autonomous on-device / BYOK AI coaching layer.

- **Working Branch:** `fitness-engine-v2`
- **Simulator Target:** iPhone 17 Pro (`B29C47DD-D3FE-490C-9A84-3D9A32AFE68A`)
- **Strict Working Constraints:**
  - *No commits, no push ever* without explicit user permission.
  - Phased, rigorous engineering with full Swift domain logic + pixel-perfect SwiftUI views.

---

## 2. Current Implementation State & Task Ledger

### A. openGym Domain & Progression Engine (`FitnessCore`)
- **`PlateMath.swift`**: Olympic barbell (20kg/45lb), EZ bar (10kg/25lb), Trap bar (25kg/55lb), and Smith machine barbell plate calculation.
- **`RecoveryModel.swift`**: \(1 - \exp(-\text{stimulus}/\text{REF})\) saturation curve, 36h exponential half-life fatigue decay, and `ready` / `recovering` / `fatigued` muscle state classification.
- **`ProgressionRule.swift`**: Standard linear, double progression, Greyskull LP, and deload policies.
- **`StreakCalculator.swift`**: ISO week grouping, 10-year consecutive streak back-scanner with week-zero grace period, weekly adherence counters (`workoutsThisWeek`, `plannedPerWeek`, `totalWorkouts`).
- **Tests**: **136/136 unit tests passing** across 12 suites via `swift test`.

---

### B. 5-Tab Navigation System & openGym Theme (`FitnessTracker`)
- **`Theme.swift`**: Color tokens (`#000000` pitch black, `#0e0e10` elevated backdrop, `#1c1c1e` cards, `#2c2c2e` controls, `#30d158` green, `#ff9f0a` orange, `#ffd60a` yellow, `#0a84ff` blue, `#bf5af2` purple).
- **`CustomTabBar.swift`**: 5 bottom tabs:
  1. `Home`
  2. `Plan`
  3. **Center Elevated Green Action Button (`Start` / `Resume`)**
  4. `Stats`
  5. `Exercises` (Library)
- **`RootView.swift`**: Coordinates 5 tabs with full-screen live workout runner.

---

### C. Pixel-Perfect Screens & Charts
- **`HomeView.swift`**:
  - `openGym` title ($32\text{pt}$ bold white) with date subline and settings gear.
  - 7-day week strip with Mon–Sun columns, green circular pill for today (`2`), and nested Today session row with barbell glyph and green `Start` capsule tag.
  - Body weight card with target goal badge (`🎯 77`), `+ Log` button, massive $40\text{pt}$ headline (`78.7 kg`), $\Delta$ indicator, and `OpenGymLineChart`.
  - Streak card with orange flame icon, `13 week streak`, and calendar trigger.
- **`OpenGymLineChart.swift`**: Smooth green curve, dashed yellow goal line with label, gradient fill fading downwards, and active endpoint.
- **`WorkoutTabView.swift` & `SessionFocusView.swift`**:
  - Live session header with duration and set counter.
  - Tactile Set Table with green circular set badges, weight and rep steppers, warmup toggle, and circular glowing green completion button.
- **`StatsView.swift` & `MuscleMapView.swift`**:
  - Side-by-side **Anterior** and **Posterior** vector body map rendered via Canvas affine matrix transform.
  - 52-week activity heatmap, 3-mode picker (`Muscle balance`, `Fatigue`, `Strength`), and RIR statistics.
- **`PlanView.swift`**: Monday through Sunday schedule breakdown, split routines, and RP volume target rows.
- **`LibraryView.swift`**: Search bar, muscle filter pills, equipment filter pills, and exercise list cards with thumbnails and detail triggers.

---

### D. Interactive Modal Sheets
- **`WeightInputView.swift`**: Reusable weight stepper with $-/+$ buttons, quick pills (`[ −1 ]`, `[ −0.5 ]`, `[ +0.5 ]`, `[ +1 ]`), and continuous slider.
- **`LogWeightSheet.swift`**: Sheet to log body weight with recent weigh-in list and red trash delete buttons.
- **`TargetWeightSheet.swift`**: Sheet to set/remove weight goals.
- **`CalendarSheet.swift`**: Full-month calendar sheet with previous/next month navigation, month total metrics (workouts, duration, tonnage), day tiles with trained/planned/rescheduled dots, and legend.
- **`DayOverrideSheet.swift`**: Modal sheet to reschedule a specific day to Push/Pull/Legs or Rest.
- **`WorkoutDetailSheet.swift`**: Summary modal of a trained day showing completed sets, duration, tonnage, PR badges, and session notes.

---

### E. openGym 1,324 Exercise Database & Media Pipeline
- **`catalog.json`**: Complete 1,324 open-source exercise database (`hasaneyldrm/exercises-dataset`, MIT) with target muscles, secondary assisting muscles, equipment categories, and step-by-step instructions.
- **`FreeExerciseDBMapper.swift`**: Robust mapping of all openGym target muscles and equipment types.
- **`ExerciseMediaView.swift`**:
  - `ExerciseThumbnailView`: Asynchronous CDN photo loader with caching and fallback glyphs.
  - `AnimatedGifView`: Hardware-accelerated inline animated GIF player with `GIF / Still` toggle.
- **`ExerciseDetailSheet.swift`**: High-resolution image/GIF banner, muscle/equipment chips, and numbered technique instructions.

---

### F. Unified Settings Suite (`SettingsView.swift`)
- **Your Data**: SwiftData local-first architecture.
- **AI Coach**: LLM provider manager (OpenAI, Gemini, Ollama, Anthropic), Keychain API key security, real-time token cost tracker, plan regenerator.
- **Athlete Profile**: Goal, experience, session length, sessions/week, and equipment inventory.
- **General Preferences**: Weight unit (`kg`/`lb`), Week start day (`Monday`/`Sunday`).
- **During a Workout**: Default rest timer, rest-pause timer, keep screen awake (`UIApplication.shared.isIdleTimerDisabled`), audio/haptics, timer flash, Effort tracking (`Off`/`RIR`/`RPE`) with Effort Scale Help Sheet.
- **Appearance**: Male/Female body diagram model, Accent color swatches (`Lime`, `Orange`, `Yellow`, `Blue`, `Purple`).
- **Data & Backups**: Load starter PPL split, Export JSON backup via iOS Share Sheet, Reset everything confirmation.

---

## 3. Roadmap & Next Steps

1. **Live Floor Workout Run-Through**: Verify live set logging, rest countdown timer, and session completion finalization with the new 1,324 exercise catalog.
2. **AI Adaptation Ingestion**: Integrate workout history snapshots into the AI planner to suggest automatic weight/rep progressions based on logged RIR/RPE.
3. **Keep Strict Working Constraints**: No uncommitted git operations (`No commits, no push ever`).
