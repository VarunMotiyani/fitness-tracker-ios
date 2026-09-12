# HANDOFF — Read This First

_Living document. Last updated: 2026-09-08 (Session progress: navigation polish, AI-provider validation, and Athlete Profile slice on branch `fitness-engine-v2`)._

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

## 1A. Session Progress — 2026-09-07

This session focused on stabilizing the app’s navigation and AI-provider path.

### Completed

- Added a dedicated **Athlete Profile** destination from Home and Settings. It owns editable identity, goal, experience, schedule, equipment, areas to avoid, and the current manual body-composition snapshot.
- Added optional current-composition fields to `UserProfile`: PBF, skeletal muscle mass, body-fat mass, fat-free mass, total body water, protein, minerals, BMR, visceral-fat level, InBody score, waist–hip ratio, and phase angle. BMI is derived, never stored.
- Saving a changed manual weight now upserts one same-day `BodyweightEntryModel`, preserving the existing bodyweight trend without duplicate readings.
- Kept plan updates explicit: Profile changes planner inputs, but only **Regenerate weekly plan** replaces the saved plan. Individual routines and the weekly schedule remain in the Plan tab.
- Moved daily check-in from the crowded Home header to a visible Home card; Home now exposes Profile, Coach, and Settings as three equal top actions.
- InBody scan camera/photo upload, scan history, and AI extraction remain deliberately deferred. The next scan slice will review values before it updates these same Profile fields.
- Reworked the persistent bottom navigation to five equal slots: Home, Plan, centered Start, Stats, and Exercises. Coach remains available from Home’s top conversation control.
- Added shared bottom-tab safe-area clearance to provider settings so the “Set as active” action is visible above the persistent bar.
- Removed the manual Model ID input for Apple on-device profiles; Apple profiles now persist the OS-selected `"system"` model identifier.
- Confirmed Apple Foundation Models support is implemented in the codebase. The iPhone simulator cannot run it because its Foundation Model assets are unavailable; validation requires a compatible physical Apple Intelligence device.
- Diagnosed Groq/Qwen failures from simulator evidence: the endpoint and API key path reached Groq successfully, but the first request failed with HTTP 400 because descriptive app schemas were sent as strict `json_schema`. After switching to JSON Object Mode, Qwen returned a direct JSON object with a `message` field rather than the tool-loop envelope and `reply` field.
- Updated the OpenAI-compatible adapter to use strict JSON Schema only when the supplied schema is strict-compatible, otherwise using JSON Object Mode with an explicit JSON-only instruction.
- Updated tool-loop and Coach DTO decoding to accept direct final objects and Qwen’s `message` alias.
- Preserved safe transport diagnostics in interactive Coach errors.
- Verified the live Groq/Qwen path in the iPhone 17 Pro simulator: “Can you reply?” returned “Yeah, I’m here. What’s up?” ([live screenshot](/private/tmp/pulseai-qwen-working.png)).
- Captured visual verification for the provider editor safe-area fix ([screenshot](/private/tmp/pulseai-provider-safe-area-fix.png)) and the final five-tab Home layout ([screenshot](/private/tmp/pulseai-final-verification.png)).

### Verification

- `swift test --package-path FitnessCore --filter ToolLoopSchemaTests` — 6 tests passed.
- Focused iOS tests for `AskCoachDTOTests`, `OpenAICompatibleProviderTests`, `ToolLoopRunnerTests`, and `ProviderProfileTests` passed.
- Focused iOS tests for `UserProfilePersistenceTests`, `UserProfileMappingTests`, and `AthleteProfileDraftTests` passed; the Profile Home and editor flows were also reviewed in the iPhone 17 Pro simulator.
- The full repository test suite was not rerun in this session; verification stayed scoped to the changed paths.

### Review guardrails to carry forward

- Trace every user-visible path end to end: the data source, filtering predicate, tap target, and destination screen must use the same eligibility rules. Shared display helpers are preferred over duplicated filters.
- Keep cancellation separate from provider failure. A cancelled task must not create a failed-provider billing or reliability record.
- Treat deduplication as a state transition: preserve the most authoritative provenance, prevent duplicate IDs in one batch, and reject empty or whitespace-only durable statements.
- Do not call safety/validation logic with placeholder context. Thread the real profile, equipment, exclusions, and historical performance data through the coordinator.
- For platform integrations, test the actual wire representation (URL canonicalization, date/time zone semantics, response envelopes, aliases, and strict-schema requirements), not only happy-path fixtures.
- Before calling a change complete, run focused tests for the changed paths and verify any UI change in the simulator with a screenshot or live interaction.

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
- **`CSVParser.swift` & `ExternalAppImporter.swift`**: RFC 4180 pure Swift CSV parser and multi-app importer auto-detecting **Hevy**, **Strong**, **FitNotes (iOS/Android)**, and generic CSV formats with unit conversion and session grouping.
- **`AppleHealthXMLImporter.swift`**: SAX streaming XML parser extracting Apple Health body mass records.
- **`MuscleBalanceModel.swift`**: 18 canonical muscle model with 40+ alias normalization map, 0.4 secondary volume weighting, body part distribution (`arms`, `deltoids`, `chest`, `back`, `legs`, `core`), load calculation, and workout ranking.

---

### B. Navigation & Theme Engine (`FitnessTracker`)
- **App Branding:** **PulseAI** header branding with personalized athlete greeting support.
- **`GymTheme.swift` / `Theme.swift`**: True pitch black (`#000000`), elevated card surfaces (`#1c1c1e`), control surfaces (`#2c2c2e`), and dynamic reactive accent themes (`Lime`, `Cyan/Sky`, `Orange`, `Violet`, `Pink`, `Red`, `Teal`, `Gold`).
- **`CustomTabBar.swift` & `RootView.swift`**: Persistent 5-tab bar with elevated center action button (`dumbbell.fill` FAB / `Start` / `Resume`), pulsing orange resume ring (`scaleEffect 1.0 -> 1.45`, `opacity 0.7 -> 0.0`, 1.9s ease-out) when a workout is active, `viewfade` tab-switch transition (`.opacity.combined(with: .offset(y: 4))`), and `list.bullet` Exercises icon.
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
- **`RoutineEditView.swift` & `DayAssignSheet.swift` & `ExerciseConfigSheet.swift` & `IconPickerSheet.swift` & `PlanShareSheet.swift`**: Full suite of routine authoring, exercise parameter customization, schedule assignment, equipment profile filtering on exercise catalog pickers, and JSON export/import.

---

### E. Tactile Gym-Floor Workout Runner & Active Modifiers
- **`SessionFocusView.swift`**:
  - Top Session Header: `✕` close/minimize button, routine name (`Push Day`), live elapsed timer (`mm:ss`), total sets counter (`0/12 sets`), and `✓` finish workout button.
  - Pinned total-set progress bar beneath header.
  - Clean Media Stage with **"⤢ Expand"** pill opening `ExerciseMediaZoomSheet.swift`.
  - Exercise Title (~28pt bold) + `ⓘ` info sheet + note pencil + plate math button.
  - Meta Chips: `[Chest]` `[Barbell]` `[Best: 85.0 kg]`.
  - "Last time" recap line: `🕒 Last time (30 Aug): 73.8×8, 73.8×8...`.
  - "Why" autoregulation progression rationale banner.
  - **"Make superset with next"** toggle button.
  - **Exercise Swap**: Seamless swap sheet with muscle group & equipment profile filters and in-place active workout replacement via `SessionRunner.swapExercise`.
  - **All-Sets Editable Table**: Every set (completed + upcoming planned) is an active row with `[− weight +]` `[− reps +]` `[− RIR +]` steppers and `○` check circle.
  - Inline Set Actions: `🔥 Add warm-up set`, `− Remove set`, `+ Add set`.
  - `WorkingWeightSheet.swift`: Post-exercise working-weight confirmation sheet with personal record detection.
  - `RestTimerView.swift`: Rest countdown with warning tick (`1052`) on $\le 3\text{s}$, completion chime (`1005`) on zero, haptic pulses, and hook to flash overlay.
  - `TimerFlashOverlay.swift`: Visual expiration $2.4\text{s}$ alternating 4-flash sequence (black/white) and `keepAwake` idle timer lock.

---

### F. Data Management, Multi-App Importers & Equipment Profiles
- **`HevyAPIClient.swift` & `HevyAPISyncSheet.swift`**: Direct REST synchronization with Hevy Developer API (`api.hevyapp.com/v1/`) with real-time sync progress and SwiftData ingestion.
- **`EquipmentModels.swift` & `EquipmentProfileSheet.swift`**: Equipment profile manager supporting named custom equipment environments (Commercial Gym, Home Dumbbells, Travel Hotel) and library/swap/picker filtering via `EquipmentFilter.isAvailable`.
- **`HistoryExportManager.swift`**: Generates full RFC 4180 CSV workout logs and reference app-compatible complete JSON backup archives.
- **`HistoryIngestionService.swift`**: SwiftData service mapping imported external sessions into `CompletedSessionModel`, `CompletedEntryModel`, `LoggedSetModel`, and `BodyweightEntryModel`.

---

### G. Stats, History & Exercises
- **`ActivityHeatmapView.swift`**: 52-week horizontal grid aligned to week start with 5-level intensity gradient and "Less time / More time" legend.
- **`InteractiveBodyMapView.swift`**: Interactive front/back anatomical body map powered by `MuscleBalanceModel` with precision volume set credits and status levels.
- **`HistoryListView.swift`**: Complete history list with "＋ Log past workout" toolbar action wired to `BackfillEntryView.swift`.
- **`LibraryView.swift` & `ExerciseDetailSheet.swift`**: 1,324 exercise catalog with equipment profile filtering, animated GIF players, and still illustration fallback.

---

## 3. Test Suite Verification

The totals below are the last recorded full-suite baseline. The 2026-09-07 session intentionally used focused verification only.

- **`FitnessCore`**: **201/201 tests passed (27 suites) in 0.007s**.
- **`FitnessTrackerTests`**: **64/64 tests passed (16 suites) in 1.1s** on iOS Simulator.
- **`FitnessTrackerUITests`**: **5/5 tests passed in 10.4s** on iOS Simulator.
- **Total Tests**: **270 Automated Tests Passing 100%**.

---

## 4. What to Do Next

1. **Live Activity & Lock Screen Dynamic Island**: Background rest timer countdown and live workout tracking for Dynamic Island (`ActivityKit`).
2. **HealthKit Bi-Directional Sync**: Sync bodyweight and completed workouts with Apple Health.
3. **Audio / Voice Coaching**: Spoken rest countdown and set completion cues.
