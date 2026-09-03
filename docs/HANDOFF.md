# HANDOFF — Read This First

_Living document. Last updated: 2026-09-03 (PulseAI Full Architecture, Proactive AI Trainer UI/UX & Native Persistence on branch `fitness-engine-v2`)._

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
- **`CustomTabBar.swift` & `RootView.swift`**: Persistent 5-tab bar with elevated center action button (`Start` / `Resume`).
- **Inline Settings Navigation**: Settings is rendered directly within the `RootView` navigation hierarchy rather than presenting as a covering modal sheet, ensuring the bottom tab bar is permanently accessible and mounted.

---

### C. Workout Runner, History & Intensifiers
- **`WorkoutTimers.swift`**: Rest timer and timed hold work countdowns with sound cues, haptics, and background notifications.
- **`DropSetRow.swift` & `RestPauseRow.swift`**: Inline UI for drop sets (-20% load) and rest-pause bursts (15s rest).
- **`BackfillEntryView.swift`**: Dedicated interface for logging past workouts with routine picker, date/time selector, and duration stepper.
- **`ExerciseNoteSheet.swift` & `SessionNoteSheet.swift`**: 3-tier exercise note viewer/editor and overall session reflection editor.

---

### D. Home Dashboard & Interactive Week Calendar
- **`HomeView.swift`**:
  - `PulseAI` headline with wide weekday/date header and settings button.
  - **Interactive 7-Day Week Strip**: Paginates weeks (`< This week >`), shows active day indicators, and lets the user tap ANY day to open `DayOverrideSheet` (to reschedule, swap split routines, or mark rest) or view completed workout details.
  - **Nested Today Routine Card**: Displays planned focus (`Push Day`, `Pull Day`, `Legs Day`) with direct `Start` action trigger.
  - **Body Weight Card**: Target goal badge (`🎯 77`), `+ Log` button, $40\text{pt}$ readout (`78.3 kg`), delta indicator, and 30-day bezier curve chart.
  - **Streak Card**: Orange flame badge, week streak counter, weekly completion count, and full-month calendar modal trigger.
- **`ActivityHeatmapView.swift`**: 52-week horizontal grid aligned to week start with relative volume/duration day shading.
- **`OpenGymLineChart.swift`**: Hand-rolled bezier line chart with gradient fill, dashed goal line, and active endpoints.

---

## 3. Test Suite Verification

- **`FitnessCore`**: **191/191 tests passed (25 suites) in 0.007s**.
- **`FitnessTrackerTests`**: **59/59 tests passed (13 suites) in 1.41s** on iOS Simulator.
- **Total Tests**: **250 Automated Tests Passing 100%**.

---

## 4. What to Do Next

1. **Live Activity & Lock Screen Dynamic Island**: Background rest timer countdown and live workout tracking for Dynamic Island.
2. **HealthKit Bi-Directional Sync**: Sync bodyweight and completed workouts with Apple Health.
3. **Audio / Voice Coaching**: Spoken rest countdown and set completion cues.
