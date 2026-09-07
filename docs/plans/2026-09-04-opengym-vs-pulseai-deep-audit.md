# openGym vs PulseAI — deep audit (backend, logic, UI, animation, sound)

Source-level comparison: `/Users/vmotiyani/Documents/person/opengym` (frontend/, api/, mcp/) vs this repo. Screen-by-screen visual diff already lives in [2026-09-04-opengym-vs-pulseai-screen-diff.md](2026-09-04-opengym-vs-pulseai-screen-diff.md) — this doc covers what that one doesn't: **backend/architecture, engine-logic module parity, animation/transition/sound fidelity**, plus two functional gaps found while tracing "is this wired up."

---

## 1. Backend / architecture — structural, not a bug list

openGym is a self-hostable client-server app: `api/` (Node stdlib HTTP server, `server.js`), WebAuthn/passkey multi-user auth, server-side JSON storage, push notifications (`api/push-messages.js`, VAPID web-push), Docker/`docker-compose.yml`, an admin panel (`views/Admin.jsx`), and `mcp/` — an **MCP (Model Context Protocol) server** exposing the user's training data to AI agents.

PulseAI is deliberately local-first single-device SwiftData: no server, no accounts, no passkeys, no push (local `UNUserNotificationCenter` reminders only), no admin panel, no MCP server. Settings literally says "All data stays on this device."

| Capability | openGym | PulseAI | Verdict |
|---|---|---|---|
| Multi-device sync | server + passkey auth | none | ❌ missing, but **out of scope by design** unless you want to add a backend |
| Push notifications | VAPID web-push, works while app is closed | local notifications only (app must have scheduled them) | 🔶 partial — fine for single-device |
| Admin/multi-user panel | `views/Admin.jsx` | n/a (single user) | not applicable |
| MCP server (AI agents read training data) | `mcp/` directory | none — but `LLMKit`/`CoachMemory` in `FitnessCore` are the seed for an AI layer (parked `phase-2c-i-ai-session-finalize` work) | 🔶 real gap if you want external agents/automation querying PulseAI data; not needed for the app itself |
| Guest/demo mode without account | `guest.js` | n/a (no accounts to guest around) | not applicable |

**Recommendation:** don't chase backend parity — it contradicts the product's local-first pitch. The one piece worth revisiting later is MCP, since it would let *your own* AI coach layer (the parked LLMKit work) query PulseAI's data the same way openGym lets external agents query it — but that's a Phase-2c-adjacent decision, not a UI-parity one.

---

## 2. Engine-logic module parity (`frontend/src/lib/*.js` vs `FitnessCore`)

Most of the training-science engine is ported (confirmed by file presence + `OpenGymProgressionParityTests` passing):

| openGym | FitnessCore | |
|---|---|---|
| `progression.js` | `RuleEngine/ProgressionRule.swift` | ✅ |
| `onerm.js` | `Metrics/Estimated1RM.swift` | ✅ |
| `supersetFlow.js` | `RuleEngine/SupersetFlow.swift` | ✅ |
| `workout-model.js` | `RuleEngine/SetRowOps.swift`, `ActiveWorkoutEdits.swift` | ✅ |
| `recovery.js` | `Metrics/RecoveryModel.swift` | ✅ |
| `bar.js` | `Metrics/PlateMath.swift` | ✅ |
| `backfill.js` | `Metrics/BackfillOps.swift` | ✅ |
| `session-start.js` | `RuleEngine/SessionEntryBuilder.swift` | ✅ |
| `rep-range.js` | `RuleEngine/RepRangeNormalize.swift` | ✅ |
| `week-start.js` | `Metrics/WeekKey.swift` | ✅ |
| `finish-workout.js` | `SessionRunner.finish()` (app layer) | ✅ (different layer, same job) |
| `import-csv.js` / `import-hevy.js` | `FitnessDomain/Import/CSVParser.swift`, `ExternalAppImporter.swift`, `HevyAPISyncSheet` | ✅ recently added |
| `plan-share.js` | `PlanShareSheet.swift` | ✅ |
| `starter.js` | `StarterRoutines` | ✅ |
| `wakelock.js` | `isIdleTimerDisabled` in `SessionFocusView` | ✅ |

**Not ported / no equivalent found:**

| openGym file | What it does | PulseAI status |
|---|---|---|
| `muscles.js` (326 lines) | effective-set volume model, 18-muscle alias table, per-exercise muscle-fraction weighting for the muscle-balance view | 🔶 partial — `EffortAnalyticsEngine`/Stats compute *something* per-muscle, but no dedicated alias/fraction table was found; worth a direct comparison pass since muscle-balance numbers may not match openGym's weighting |
| `equipment.js` | `exAvailable(S, ex)` — filters the catalogue/picker to what an active equipment profile can do; bodyweight always passes | ❌ **written but never wired** — see §4.1 below, it's a real functional gap, not a design choice |
| `hevy-id-map.js` (576 lines) | maps openGym's internal exercise IDs ↔ Hevy's exercise IDs for import matching | 🔶 unclear if `HevyAPISyncSheet`/`Import/` has an equivalent mapping table or relies on name-matching only — worth checking if Hevy imports are matching correctly for renamed/aliased exercises |
| `history.js` (652 lines) | session history querying/grouping/search used by `views/History.jsx` | 🔶 `HistoryListView.swift` + `Metrics/*` cover pieces of this; no single audited equivalent |
| `progression-copy.js` | maps a progression `Prescription` to the exact human-readable rationale string | ✅ have `WhyTemplate` in `ProgressionRule.swift` — copy differs in phrasing/color (orange vs openGym's yellow) but the mechanism exists |
| `recovery-view.js` | maps `RecoveryModel` state → UI color/text for the fatigue/strength map | ✅ equivalent logic lives inline in `StatsView.swift`'s `fatigueView`/`strengthView` |
| `audit.js` | local-storage integrity check/repair tool | not applicable — SwiftData doesn't need a JSON-file repair tool the way openGym's browser-storage backend does |
| `i18n.js` / `i18n-core.js` + 14 locale files | full internationalization | ❌ PulseAI is English-only — a real gap if you want non-English users, unscoped otherwise |
| `sound.js` | WebAudio beep + `navigator.vibrate` on rest-timer completion | 🔶 see §3.3 — a native equivalent exists in the codebase but isn't wired to the live timer |
| `nav.js`, `back.js`, `use-sheet-keyboard.js`, `mobile.js` | hash-router nav, Android back-button handling, virtual-keyboard-avoiding sheets, Capacitor mobile glue | not applicable — `NavigationStack`, hardware back gesture, and keyboard avoidance are all native-platform behavior on iOS |
| `guest.js`, `push.js`, `remote.js` | guest mode, web push, self-hosted sync client | not applicable without a backend (§1) |

---

## 3. Animations, transitions, haptics, sound

openGym's `frontend/src/index.css` defines 6 keyframe animations. Each maps to a specific interaction:

| openGym keyframe | Where used | PulseAI | Status |
|---|---|---|---|
| `viewfade` (`opacity 0→1` + `translateY(4px)→0`, applied to `#app.vfade` on **every route change**) | every tab switch / navigation | `RootView.swift:136-137` — `Group { switch selectedTab { … } }` with **no `.transition`/`.animation` modifier at all** | ❌ **missing** — tab switches are a hard cut, openGym fades+slides every one |
| `ping` (orange ring, `scale 1→1.45` + `opacity .7→0`, `1.9s infinite`) | pulses around the Start/Resume button when a workout is paused, to draw the eye back to it | `CustomTabBar.swift` only changes the FAB's **shadow color** (orange vs accent) when `isWorkoutActive` — no animated ring | ❌ **missing** — the "come back to your workout" affordance is static, not pulsing |
| `slideup` (`translateY(16px)→0` + fade, `var(--med)`) | rest-timer banner appearing | `RestTimerView` — inserted into the VStack with no explicit `.transition` | 🔶 **missing** — timer just appears/disappears, no slide |
| `sheetup` (bottom-sheet slide from 100%) | all bottom sheets | native `.sheet()` presentation | ✅ platform default covers this |
| `pop` (center-modal scale .94→1 + fade) | center dialogs (confirmations) | native `.alert`/`.confirmationDialog` | ✅ platform default covers this |
| `timer-flash-four` (2.4s, **alternating black/white** flash 4 times, precise keyframe %s) | screen flash when the rest timer ends — a visual alarm that works even muted, from across the room | `TimerFlashOverlay.swift` — `Color.white.opacity()` only (never flashes black), driven by `.easeInOut(duration:0.12).repeatCount(4, autoreverses:true)` ≈ **~1s total**, not 2.4s, and only one color | 🔶 **approximation, not a port** — see exact fix below |

### 3.1 Fix target for `TimerFlashOverlay`

openGym's curve (`@keyframes timer-flash-four`, 2.4s):
```
0%,20%,28%,48%,56%,76%,84%,100% → opacity 0   (dark gaps)
4%,16%,60%,72%                  → black flash, opacity 1
32%,44%,88%,96%                 → white flash, opacity 1
```
Four flashes, alternating black then white, each ~4% (≈96ms) wide, evenly spaced across 2.4s. Current Swift version is a single repeated white pulse at less than half the duration. To match: build an explicit `Animation` timeline (or a small state machine driven by a `Timer`/`Task.sleep` sequence) that alternates the overlay color between `.black` and `.white` at those four moments, total ~2.4s.

### 3.2 Missing: pulsing "resume" ring

`CustomTabBar.swift`'s center button needs an animated ring, not just a static shadow tint, when `isWorkoutActive`:
```swift
Circle()
    .stroke(GymTheme.orange, lineWidth: 2)
    .scaleEffect(pulse ? 1.45 : 1.0)
    .opacity(pulse ? 0 : 0.7)
    .animation(.easeOut(duration: 1.9).repeatForever(autoreverses: false), value: pulse)
```
(with `pulse` flipped `true` once on `.onAppear` when `isWorkoutActive`).

### 3.3 Rest-timer sound is dead-code, not wired

Two separate rest-timer implementations exist:
- **`Features/Session/RestTimerView.swift`** — the one actually used by `SessionFocusView` (`@State private var restTimer = RestTimer()`). Its completion path, `fireCompletionHaptic()` (`:101-106`), fires **haptic only** (`UINotificationFeedbackGenerator().notificationOccurred(.success)`) — no sound. There's even a `// TODO(phase4): local notification when backgrounded` left in place.
- **`Session/WorkoutTimers.swift`** — has the *correct* behavior (`AudioServicesPlaySystemSound(1052)` warning tick + `AudioServicesPlaySystemSound(1005)` completion + haptic) matching openGym's `beep(S.sound, 1040, 0.12); vibrate(30)` on rest-timer end — but **this type is referenced nowhere else in the codebase**. It's dead code.

Fix: port `WorkoutTimers.swift`'s sound calls into the live `RestTimer` class in `RestTimerView.swift` (or delete `WorkoutTimers.swift` and confirm nothing depended on it), so the timer that's actually on screen makes a sound when it ends, not just a haptic buzz.

### 3.4 Tab/view transition — quick fix

Add to `RootView.swift`'s tab content:
```swift
Group {
    switch selectedTab { … }
}
.id(selectedTab)
.transition(.opacity.combined(with: .move(edge: .bottom)).animation(.easeOut(duration: 0.22)))
```
(a `.move(edge: .bottom)` combined with opacity approximates the 4px-translateY fade openGym uses; `.id(selectedTab)` forces SwiftUI to actually animate the swap instead of diffing in place.)

---

## 4. Functional gaps found while tracing "is this wired up"

### 4.1 Equipment-filter toggle is write-only — the whole feature is inert

`EquipmentProfileSheet.swift` is the **only** file in the app that touches `gym_equip_filter_on`, `gym_active_profile_id`, or `gym_equipment_profiles_json`:
```
grep -rl "gym_equip_filter_on" .   →  EquipmentProfileSheet.swift  (only hit)
```
openGym's equivalent (`equipment.js`'s `exAvailable(S, ex)`) is consumed by the exercise catalogue and every exercise picker to hide equipment you don't have. In PulseAI, you can build multiple equipment profiles, mark one active, flip "Filter by equipment" on — and **nothing changes**: `LibraryView`, `ExercisePickerSheet` (Stats), and `ExerciseSwapSheet` (workout runner) all list every exercise regardless. This is a fully-built Settings screen wired to nothing downstream — worth fixing before shipping Settings, since a user who turns that toggle on will reasonably expect it to do something.

**Fix shape:** a small `EquipmentFilter.isAvailable(_ exercise: Exercise, profiles: [EquipmentProfile], activeID: String, filterOn: Bool) -> Bool` helper (port of `exAvailable`, bodyweight always passes) in `FitnessCore` or `ExerciseCatalog`, then apply it as an extra filter predicate in `LibraryView.searchAndMuscleMatches`, `ExercisePickerSheet`'s exercise list, and `ExerciseSwapSheet`'s candidate list.

### 4.2 Muscle-balance weighting — unverified against `muscles.js`

`muscles.js` is a 326-line effective-set volume model with an 18-muscle alias table (mapping many exercise-catalog muscle-name variants onto a canonical 18-muscle set) and per-exercise fractional muscle credit (a compound gets partial credit split across several muscles, not one full "set" per muscle). `StatsView`'s muscle-balance view computes *some* per-muscle set count (`muscleSetCountsInWindow`), but I didn't find a matching alias table or fractional-credit model in `FitnessCore`/`ExerciseCatalog`. Worth a dedicated pass: pull up `muscles.js`'s alias table and effective-set formula side-by-side with whatever currently drives `muscleSetCountsInWindow` and confirm the numbers agree, since a wrong muscle-balance chart is a quiet correctness bug (users trust it to say what's undertrained).

---

## Ranked worklist (new items from this pass, on top of the screen-diff doc's list)
## Ranked worklist — Status: ALL RESOLVED (2026-09-04)

1. **§4.1 wire the equipment filter** — currently a fully-built no-op feature; either finish it or the toggle is misleading.
2. **§3.3 fix rest-timer sound** — the shipped timer is silent by mistake (haptic-only), dead code already has the right implementation sitting unused.
3. **§3.1 fix `TimerFlashOverlay`** — wrong color (white-only vs black+white alternating) and roughly half the intended duration.
4. **§3.4 add a tab-switch transition** — every screen change is currently a hard cut.
5. **§3.2 add the pulsing resume ring** — the "you have an unfinished workout" affordance is static.
6. **§4.2 verify muscle-balance math** against `muscles.js`'s alias table + effective-set formula.
1. ✅ **§4.1 wire the equipment filter** — Ported `equipment.js` logic to `EquipmentFilter`, wired across `LibraryView`, `ExerciseSwapSheet`, `StatsView` (`ExercisePickerSheet`), and `RoutineEditView` (`ExercisePickerCatalogSheet`). Verified with unit tests.
2. ✅ **§3.3 fix rest-timer sound** — RestTimer now triggers `AudioServicesPlaySystemSound(1052)` warning ticks (<=3s) and `AudioServicesPlaySystemSound(1005)` completion chime alongside success haptic, respecting user sound preference.
3. ✅ **§3.1 fix `TimerFlashOverlay`** — Implemented openGym's exact 2.4s `@keyframes timer-flash-four` sequence alternating black and white flashes (96ms..384ms black, 768ms..1056ms white, 1440ms..1728ms black, 2112ms..2304ms white).
4. ✅ **§3.4 add a tab-switch transition** — Implemented `.id(selectedTab)` and `.transition(.opacity.combined(with: .offset(y: 4)))` with 220ms ease-out animation in `RootView.swift` matching `@keyframes viewfade`.
5. ✅ **§3.2 add the pulsing resume ring** — Implemented expanding animated ring (`scaleEffect 1.0 -> 1.45`, `opacity 0.7 -> 0.0`, 1.9s infinite ease-out) behind center Start/Resume FAB in `CustomTabBar.swift` matching `@keyframes ping`.
6. ✅ **§4.2 verify muscle-balance math** — Ported `muscles.js` directly to `MuscleBalanceModel` with 18 canonical muscles in head-to-toe order, 40+ alias dictionary, 0.4 secondary muscle factor, body part fallback distribution, `loadOf`, `levelsOf`, and `rankOf`. Integrated into `StatsView.swift` and `InteractiveBodyMapView.swift`. 100% verified with dedicated test suite.
7. (unscoped, discuss before doing) — i18n, MCP server, backend sync are real capability gaps but are architecture decisions, not bugs.

