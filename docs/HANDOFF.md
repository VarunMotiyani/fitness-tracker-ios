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
- **`ProgressionRule.swift`**: Linear progression, double progression, Greyskull LP, and automatic deload policies.
- **`StreakCalculator.swift`**: ISO-8601 calendar week scanner, 520-week backward scan with grace periods, and weekly adherence rollups (`workoutsThisWeek`, `plannedPerWeek`, `totalWorkouts`).
- **`PlanCoordinator.swift` & `PlanPromptBuilder.swift`**: Coordinates rule-based starter routines with BYOK AI planning (Gemini / OpenAI compatible) with strict JSON schema constraints and retry loops.

---

### B. Navigation & Theme Engine (`FitnessTracker`)
- **App Branding:** **PulseAI** header branding with personalized athlete greeting support.
- **`GymTheme.swift`**: True pitch black (`#000000`), elevated card surfaces (`#1c1c1e`), control surfaces (`#2c2c2e`), and dynamic reactive accent themes (`Lime`, `Cyan/Sky`, `Orange`, `Violet`, `Pink`, `Red`, `Teal`, `Gold`).
- **`CustomTabBar.swift` & `RootView.swift`**: Persistent 5-tab bar with elevated center green action button (`Start` / `Resume`).
- **Inline Settings Navigation**: Settings is rendered directly within the `RootView` navigation hierarchy rather than presenting as a covering modal sheet, ensuring the bottom tab bar is permanently accessible and mounted.

---

### C. Home Dashboard & Interactive Week Calendar
- **`HomeView.swift`**:
  - `PulseAI` headline with wide weekday/date header and settings button.
  - **Interactive 7-Day Week Strip**: Paginates weeks (`< This week >`), shows active day indicators, and lets the user tap ANY day to open `DayOverrideSheet` (to reschedule, swap split routines, or mark rest) or view completed workout details.
  - **Nested Today Routine Card**: Displays planned focus (`Push Day`, `Pull Day`, `Legs Day`) with direct `Start` action trigger.
  - **Body Weight Card**: Target goal badge (`🎯 77`), `+ Log` button, $40\text{pt}$ readout (`78.7 kg`), delta indicator, and 30-day bezier curve chart.
  - **Streak Card**: Orange flame badge, week streak counter, weekly completion count, and full-month calendar modal trigger.
- **`OpenGymLineChart.swift`**: Hand-rolled bezier line chart with gradient fill, dashed goal line, and active endpoints.

---

### D. Snug Modal Sheets (Zero Wasted Space)
- **`LogWeightSheet.swift`**:
  - Stepper buttons (`[-] 78.7 kg [+]`), delta pills (`−1`, `−0.5`, `+0.5`, `+1`), and dynamic slider track.
  - **Historical Weigh-Ins**: Renders recent entries (`Recent weigh-ins` with dates, weights, and delete trash buttons).
  - **Snug Presentation Detents**: Dynamically calculated height based on recent entries (`360 + count * 54pt`), eliminating dead black voids.
  - **Clean Header Spacing**: Top padding below sheet drag indicator preventing clipped headers.
- **`DayOverrideSheet.swift`**:
  - Header showing selected date and weekly plan assignment.
  - Routine swap list (`Session 1 · Push Day`, `Session 2 · Pull Day`, etc.), `Rest / skip this day`, and `Back to weekly plan`.
- **`CalendarSheet.swift`**: Full-month calendar grid with previous/next month navigation, month aggregate tonnage/duration rollups, trained day dots, and legend. Snug height (`445pt` or `495pt` based on month rows).
- **`TargetWeightSheet.swift`**: Fitted modal (`320pt` / `380pt`) to set, update, or remove target bodyweight goals.
- **`WorkoutDetailSheet.swift`**: Summary modal of a trained day showing completed sets, duration, tonnage, PR badges, and notes.

---

### E. Gym-Floor Workout Runner & Exercise Library
- **`SessionFocusView.swift` & `WorkoutTabView.swift`**: Tactile Set Table with green set check buttons, weight/rep steppers, rest countdown timer with audio/haptic cues, and session finalizer.
- **`LibraryView.swift` & `catalog.json`**: 1,324 exercise database with primary/secondary muscles, equipment tags, step-by-step instructions, asynchronous CDN thumbnails, and hardware-accelerated animated GIFs.
- **`StatsView.swift` & `MuscleMapView.swift`**: Canvas-rendered Anterior and Posterior vector body maps, 52-week activity heatmap, e1RM progression charts, and RIR effort analysis.

---

## 3. Roadmap & Next Steps

1. **AI Adaptive Training Suggestions**: Feed recent workout logs and RIR effort ratings into the AI coordinator to proactively suggest load/rep progression for upcoming sessions.
2. **Apple HealthKit Sync**: Add two-way sync for bodyweight measurements and active workout sessions into Apple Health.
3. **Live Activity & Dynamic Island**: Add Lock Screen and Dynamic Island live workout countdowns and rest timers.
4. **Strict Invariant Rule**: Always maintain `No commits, no push ever`.
