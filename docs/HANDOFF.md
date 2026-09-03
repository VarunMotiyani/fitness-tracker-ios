# HANDOFF — Read This First

_Living document. Last updated: 2026-09-04 (PulseAI Full Architecture, openGym Visual & Behavioral Parity, Gym-Floor Workout Runner & Native Persistence on branch `fitness-engine-v2`)._

**Purpose:** One read = full context. If you're a new agent/session on any device, read this top to bottom before doing anything. It captures the project, every decision, current state, how to work here, and what's next. Deep detail lives in the numbered docs; this is the index + digest.

---

## 1. What the project is

A **proactive AI strength & physique coaching app (PulseAI)** for iOS (iPhone 17 Pro / iOS 17+) that pairs tactile, high-efficiency gym floor mechanics with an autonomous on-device / BYOK AI coaching layer.

- **App Name:** **PulseAI** (Proactive AI Fitness Coach)
- **Working Branch:** `fitness-engine-v2`
- **Simulator Target:** iPhone 17 Pro (`B29C47DD-D3FE-490C-9A84-3D9A32AFE68A`)
- **Strict Invariant Rules:**
  - *No commits, no push ever* without explicit user permission.
  - Swift 6 Strict Concurrency + Native SwiftUI + SwiftData architecture.

---

## 2. Current Implementation State & Task Ledger

### A. Proactive AI Coaching & Progression Core (`FitnessCore`)
- **`PlateMath.swift`**: Exact barbell plate calculations for Olympic (20kg/45lb), Women's (15kg/35lb), EZ bar (10kg/25lb), Trap bar (25kg/55lb), and Smith machines.
- **`RecoveryModel.swift`**: \(1 - \exp(-\text{stimulus}/\text{REF})\) stimulus saturation curve, 36-hour exponential half-life fatigue decay, and `ready` / `recovering` / `fatigued` muscle status classifier.
- **`ProgressionRule.swift`**: Linear progression (3-miss threshold before deload), double progression (rep ceiling climb then reset), Greyskull LP (AMRAP doubling double-jump), and automatic deload policies.
- **`StreakCalculator.swift` & `WeekKey.swift`**: ISO-8601 / Sunday week start scanner, 520-week backward scan with grace periods, and weekly adherence rollups (`workoutsThisWeek`, `plannedPerWeek`, `totalWorkouts`). Single source of truth for Home and Stats.
- **`Estimated1RM.swift`**: Epley, Brzycki, and Lombardi formulas capped at 12 reps, `series`, `best`, and `isRecord` detection.
- **`EffortAnalyticsEngine.swift`**: 5-rated set minimum floor for summary statistics, weekly drop-below-2 rated sets filter, and hard set histogram (RIR 0..3 vs 4+).
- **`SupersetFlow.swift` & `SetRowOps.swift`**: Superset unit grouping, step cycling, rest calculation (longest member), drop-sets, and rest-pause clusters.
- **`SessionEntryBuilder.swift` & `BackfillOps.swift`**: Unified session entry construction for live start and past workout logging with chronological insert and replacement.
- **`Notes.swift` & `Scheduling.swift`**: 3 distinct note tiers (plan instruction, standing note, pinned note), effective routine resolution, and next training day calculation.

---

### B. Navigation & Theme Engine (`FitnessTracker`)
- **App Branding:** **PulseAI** header branding with personalized athlete greeting support.
- **`GymTheme.swift` / `Theme.swift`**: True pitch black (`#000000`), elevated card surfaces (`#1c1c1e`), control surfaces (`#2c2c2e`), and dynamic reactive accent themes (`Lime`, `Cyan/Sky`, `Orange`, `Violet`, `Pink`, `Red`, `Teal`, `Gold`).
- **`CustomTabBar.swift` & `RootView.swift`**: Persistent 5-tab bar with elevated center action button (`dumbbell.fill` FAB / `Start` / `Resume`), and `list.bullet` Exercises icon.
- **Inline Settings Navigation**: Settings is rendered directly within the `RootView` navigation hierarchy rather than presenting as a covering modal sheet, ensuring the bottom tab bar is permanently accessible and mounted.

---

### C. Home Dashboard & Interactive Week Calendar
- **`HomeView.swift`**:
  - `PulseAI` headline with wide weekday/date header and outline `gearshape` settings button in circular badge.
  - **Interactive 7-Day Week Strip**: Paginates weeks (`< This week >`), shows active day indicators, real-time 4-state status dots (Green = completed session, Orange = rescheduled/partial, Gray = planned, Clear = rest), and lets the user tap ANY day to open `DayOverrideSheet` or view completed workout details.
  - **Dynamic Today Routine Card**: Displays planned focus (`Push Day`, `Pull Day`, `Legs Day`) with dynamic `COMPLETED TODAY` / `TODAY` status and `Redo` / `Start` pill buttons.
  - **Body Weight Card**: Target goal badge (`🎯 77`), `+ Log` button, $40\text{pt}$ readout (`78.3 kg`), delta indicator, and chronologically sorted 30-day bezier curve chart.
  - **Streak Card**: Orange flame badge, week streak counter, weekly completion count, and full-month calendar modal trigger.

---

### D. Plan & Routine Manager
- **`PlanView.swift`**:
  - Large top title **"Plan"** (34pt bold) + subtitle **"Your weekly routine"** and top-right circular share button.
  - Sentence-case headers: **"Week schedule"**, **"Routines"**, **"Weekly volume targets"**.
  - 7-day schedule rendered as individual rounded cards with 8pt vertical spacing.
  - **"+ New"** routine button styled in green-tinted rounded capsule.
  - Split Routine Cards with icon, exercise count, and direct Start capsule.
- **`RoutineModels.swift`**: `RoutineDraft`, `ExerciseConfig`, `StarterRoutines.ppl()`.
- **`RoutineEditView.swift` & `DayAssignSheet.swift` & `ExerciseConfigSheet.swift` & `IconPickerSheet.swift` & `PlanShareSheet.swift`**: Full suite of routine authoring, exercise parameter customization, schedule assignment, and JSON export/import.

---

### E. Tactile Gym-Floor Workout Runner
- **`SessionFocusView.swift`**:
  - Top Session Header: `✕` close/minimize button, routine name (`Push Day`), live elapsed timer (`mm:ss`), total sets counter (`0/12 sets`), and `✓` finish workout button.
  - Pinned total-set progress bar beneath header.
  - Clean Media Stage with **"⤢ Expand"** pill opening [`ExerciseMediaZoomSheet.swift`](file:///Users/vmotiyani/Documents/person/fitness-tracker-ios/FitnessTracker/FitnessTracker/Features/Session/ExerciseMediaZoomSheet.swift).
  - Exercise Title (~28pt bold) + `ⓘ` info sheet + note pencil + plate math button.
  - Meta Chips: `[Chest]` `[Barbell]` `[Best: 85.0 kg]`.
  - "Last time" recap line: `🕒 Last time (30 Aug): 73.8×8, 73.8×8...`.
  - "Why" autoregulation progression rationale banner.
  - **"Make superset with next"** toggle button.
  - **All-Sets Editable Table**: Every set (completed + upcoming planned) is an active row with `[− weight +]` `[− reps +]` `[− RIR +]` steppers and `○` check circle.
  - Inline Set Actions: `🔥 Add warm-up set`, `− Remove set`, `+ Add set`.
  - [`WorkingWeightSheet.swift`](file:///Users/vmotiyani/Documents/person/fitness-tracker-ios/FitnessTracker/FitnessTracker/Features/Session/WorkingWeightSheet.swift): Post-exercise working-weight confirmation sheet with personal record detection.
  - [`TimerFlashOverlay.swift`](file:///Users/vmotiyani/Documents/person/fitness-tracker-ios/FitnessTracker/FitnessTracker/Features/Common/TimerFlashOverlay.swift): Visual expiration flashing alert.

---

### F. Stats, History & Exercises
- **`ActivityHeatmapView.swift`**: 52-week horizontal grid aligned to week start with 5-level intensity gradient and "Less time / More time" legend.
- **`HistoryListView.swift`**: Complete history list with "＋ Log past workout" toolbar action wired to `BackfillEntryView.swift`.
- **`LibraryView.swift` & `ExerciseDetailSheet.swift`**: 1,324 exercise catalog with animated GIF players and still illustration fallback.

---

## 3. Test Suite Verification

- **`FitnessCore`**: **191/191 tests passed (25 suites) in 0.006s**.
- **`FitnessTrackerTests`**: **59/59 tests passed (13 suites) in 0.77s** on iOS Simulator.
- **Total Tests**: **250 Automated Tests Passing 100%**.

---

## 4. What to Do Next

1. **Live Activity & Lock Screen Dynamic Island**: Background rest timer countdown and live workout tracking for Dynamic Island.
2. **HealthKit Bi-Directional Sync**: Sync bodyweight and completed workouts with Apple Health.
3. **Audio / Voice Coaching**: Spoken rest countdown and set completion cues.
