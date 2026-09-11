# UI/UX Audit Remediation Plan — 2026-09-11

**Source audit:** impeccable native audit, 2026-09-11 — **8/20 (Poor)**
(A11y 1 · Perf 2 · Theming 2 · Conformance 2 · Adaptivity 1)
**Scope:** all 24 findings (8 P1, 10 P2, 6 P3) + `impeccable init`
**Target score after remediation:** ≥ 16/20 (Good band)

---

## 0. What is NOT changing (brand protection)

These are deliberate identity choices. The audit flagged the surface; the fix hardens them, never replaces them:

| Kept | How it gets hardened |
|---|---|
| Dark-only, pure-black gym aesthetic (`GymTheme`, `.preferredColorScheme(.dark)`) | Tokens move to asset catalog with High-Contrast variants; literal `Color.white`/`.black` replaced with token refs so Smart Invert / Increase Contrast work |
| Floating glass `CustomTabBar` + center Start disc | Stays. 44 pt hit areas, pulse gated by Reduce Motion, plan-decode failure surfaces an error instead of hiding the bar |
| Immersive full-screen session runner | Stays. Gets labels, targets, motion gating |
| Hand-crafted feel (steppers, cards, chips) | Stays. Gets accessibility labels, not system-control replacement |

---

## Phase 0 — Product context (`$impeccable init`)

Writes `PRODUCT.md` at repo root. I run the init interview; it is 4–5 quick questions (audience, brand voice, platform intent, differentiators). Product truth already in `docs/02-product-design.md` + `docs/06-decisions.md` seeds the answers; anything unanswered is inferred from those docs and labeled as an assumption.

Also folds in the discovered inconsistency: `docs/LEDGER.md` says "Target: iPhone (iOS 17+)" but `project.pbxproj` ships `TARGETED_DEVICE_FAMILY = "1,2"` (iPad included) on deployment 26.x. PRODUCT.md records the decision below.

**Deliverable:** `PRODUCT.md`. No code changes.

---

## Phase 1 — Decision points (need your answer; recommendations shown)

| # | Decision | Options | Recommendation |
|---|---|---|---|
| D1 | iPad support | (a) declare iPhone-only (`"1"`) (b) add size-class/landscape layouts | **(a)** — matches LEDGER intent, kills 100 % of adaptivity risk at zero cost. Gym app, one hand, pocket-first |
| D2 | Rest-timer flash | (a) keep default-on but gate by accessibility settings + soften | (b) default off, opt-in | **(a)** — `UIAccessibility` reduce-motion/flashing-alerts check forces off; peak opacity 0.85 → ≤ 0.4, 4 pulses → 2, no white frames |
| D3 | Charts | (a) migrate `ProgressLineChart` + Stats charts to Swift Charts | (b) keep custom, bolt on a11y elements | **(a)** — free VoiceOver chart support, free drag-to-inspect, deletes ~250 lines of hand-drawn Path math |
| D4 | GIF rendering | (a) small pure-Skill deferred-frame decoder (Depict-style, ~40 KB SPM) | (b) hand-rolled `CGImageSource` frame pre-decode + `TimelineView` | **(b)** — zero third-party dependency, one file, ~70 lines, kills every WKWebView |
| D5 | Image caching | (a) zero-dep disk cache actor in front of `AsyncImage` | (b) Nuke/Kingfisher SPM | **(a)** — 5 call sites, thumbnails only; a full library is overkill |
| D6 | Coach entry point | (a) add Coach pill/button in Home header + delete dead `.coach` tab branch | (b) promote Coach to a real 5th tab-bar slot (drops Exercises or Plan) | **(a)** — preserves the 4-slot + disc composition |
| D7 | Home card order | Pin today's workout + Start CTA above check-in/suggestions; AI cards collapse to a count-badge stack, expandable on tap | keep current order, just shrink suggestion cards | **first option** — Start must be reachable without scroll |

Answer inline ("D1 a, D2 a, …") or just say "go with all recommendations".

---

## Phase 2 — `$impeccable adapt` (P1 ×3, P2 ×2)

### 2.1 Touch targets → 44 pt minimum
- `GymStepper.swift:39-47,70-80` — ± buttons visual 24×36; wrap labels in `.frame(minWidth: 44, minHeight: 44)` + `.contentShape(Rectangle())` (visual size unchanged, hit area grows; row spacing 6 pt absorbs overlap)
- `SessionFocusView.swift:224,261` — close/finish circles 36 pt visual → 44 pt hit via `.frame` + `contentShape`
- `SessionFocusView.swift:657` — log-set check 44×38 → 44×44
- `CustomTabBar.swift` — pill height 40 → keep visual, extend `.contentShape` into the 9 pt capsule padding (40+8×2 → 56)
- Audit pass: `rg "frame\(width: (2|3)[0-9], height: (2|3)[0-9]"` across Features/ to catch stragglers

### 2.2 Dynamic Type migration (382 fixed sizes → text styles)
Mechanical ladder, applied file-by-file, worst first (`StatsView` 79, `HomeView` 36, `SessionFocusView` 33, `PlanView` 33, `DayOverrideSheet` 31, `LibraryView` 16, then remainder):

| Fixed pt | New style |
|---|---|
| ≤ 10 (badges, chips, axis labels) | `caption2` (11) — fixes 19 sub-11-pt violations too |
| 11–12 | `caption` |
| 13 | `footnote` |
| 14–15 | `subheadline` |
| 16–17 | `body` |
| 20–22 | `title2`/`title3` |
| 24–28 | `title` |
| ≥ 34 display numerals (streak, weight hero) | `largeTitle`, `.bold()`, weight kept |

- Weights/`design: .rounded`/`.monospacedDigit()` modifiers are preserved.
- Row/card heights: replace fixed `frame(height:)` with `minHeight:` where a text style is inside; verify at AX5 in Simulator.
- **Exception list (stay fixed-size on purpose):** chart axis labels (inside `drawingGroup`, not text-flow), tab-bar glyph `size: 19`, GIF overlay "Expand" pill microcopy. Documented inline.

### 2.3 Device + orientation (after D1)
- If D1=a: `TARGETED_DEVICE_FAMILY = "1"` all 6 configs; Info.plist orientations → `Portrait` only (removes upside-down + landscape dead ends). Re-verify `xcrun simctl` launch on iPhone SE3 (smallest) + iPhone 17 Pro Max.
- If D1=b: size-class branch in `RootView` content (sidebar column on regular width) — budget note: this is 3–5× the work of (a).

### 2.4 Keyboard & focus
- `@FocusState` + `submitLabel(.done)` in: `CustomExerciseEditorSheet`, `ExerciseNoteSheet`, `SessionNoteSheet`, `ChatView` composer, `LogWeightSheet` (numpad fields already `keyboardType`), `ProviderProfileEditView`
- Note/editor sheets: `.interactiveDismissDisabled(editor.isDirty)` — swipe-away can no longer lose typed text; keep explicit Cancel
- Chat composer: `submitLabel` sends, focus persists across send

### 2.5 Verification
`xcodebuild` build + existing unit tests green; Simulator captures: home/session/library at Default + AX5 text size, dark; VoiceOver cursor walk through set-logging row reads one coherent sentence.

---

## Phase 3 — `$impeccable animate` (P1, P2 ×2)

### 3.1 Flash safety (`TimerFlashOverlay.swift`, `SessionFocusView.swift:71,123`)
- Read `UIAccessibility.flashingAlertsAreEnabled == false` or `\.accessibilityReduceMotion` → suppress strobe entirely, fall back to single 200 ms ring tint + `.notify(.success)` haptic (already present)
- Non-AX users: peak 0.85 → 0.4, drop the two white pulses (black-only, 2 pulses, 1.2 s total)
- `gym_timer_flash` setting stays (Settings copy updated: "Screen flash at rest end — reduced automatically when Reduce Motion is on")

### 3.2 Tab-bar pulse (`CustomTabBar.swift:109`)
- `@Environment(\.accessibilityReduceMotion)` → when on: static orange ring, no `repeatForever` (this also stops a permanent GPU wake while a session is active — perf side win)

### 3.3 Motion audit sweep
- `AnyTransition.viewFade` + root `.animation(.default)` toasts: no-op under Reduce Motion (add gate)
- Sheet/spring transitions stay system — untouched

### 3.4 Verification
Reduce Motion ON in Simulator: zero repeatForever animation IDs at runtime (`rg repeatForever` = 0 ungated hits), flash suppressed; haptic fires at rest end.

---

## Phase 4 — `$impeccable optimize` (P1 ×2, P2 ×2, P3 ×1)

### 4.1 Session render storm (`SessionFocusView.swift`)
- **1 Hz timer** (`:90,130`): replace `Timer.publish` always-on with `.task(id: firstLoggedSetTime)`-driven 1 s cadence, and only while a session is live and started. State writes go to `elapsedSeconds` only when the minute-value changes for the *display* — display is `m:ss`, so seconds tick still drive re-render; contain it: extract header (name + elapsed + set count) into its own small `SessionHeader` subview so the 1 Hz state invalidation re-evaluates the header, not the 944-line body
- **`lastPerformanceText` (`:906-922`)** + **`bestPerformanceText` (`:924-930`)**: compute once per exercise in `seedCurrentExercise()` into `@State lastTimeText/bestText`; body reads state. Kills O(all history) scan per render (which was running every second, per the timer fix above)
- `firstLoggedSetTime`/`allLoggedSetsCount` (`:775-785`): memoize into the same seed pass

### 4.2 Save batching (`SessionRunner.swift` — 10 `attemptSave` call sites)
- Remove per-action save; add `@Sendable` save coalescer: mark-dirty → flush at rest-timer end, exercise advance, `markDone`, `finish`, app background. Session-abandon resolve path (`RootView.swift:221`) already tolerates unsaved-tail sessions (it fetches directly); add a unit test for "quit after 2 sets, relaunch, sets present"
- `RootView.swift:369` `needsInitialSeed` sync fetch in `body`: compute in `@State` once via `.task`, body reads the flag

### 4.3 GIF native renderer (D4)
- New `Features/Common/AnimatedImageRenderView.swift`: `CGImageSourceCreateWithURL` → pre-decode ≤ 40 frames downscaled to card size (cap 480 px) off-main → `TimelineView(.periodic(from:to:after:))` index cycling; 800 ms LRU cache keyed by URL; pause when `!isVisible` (`onScrollVisibilityChange`)
- Delete `AnimatedGifView` WKWebView (`ExerciseMediaView.swift:7-61`); swap 4 call sites
- Session-screen memory: expect −1 WebContent process, −~50 MB during workouts

### 4.4 Image cache (D5)
- `CachedAsyncImage` (~50-line view + actor): sha-URL keyed files under `Caches/ExerciseThumbs/`, hit → `Image(uiImage:)`, miss → `URLSession` fetch → store → fade in; LRU trim at 60 MB
- Swap 5 `AsyncImage` sites (`ExerciseImageView.swift:14`, `ExerciseMediaView`, `ExerciseDetailSheet`, `ExerciseMediaZoomSheet`, `SessionFocusView`)

### 4.5 Query fan-out (measure, then act)
- RootView(10) + HomeView(14) `@Query` with all tabs mounted: after 4.1/4.2 fixes, measure set-log → full-tab revalidation duration with Instruments (Time Profiler, "log set" trace). If still > 8 ms: scope `@Query` to the tab that needs each model via predicate/`fetchLimit` (`previousSessions` needs `fetchLimit` + per-exercise predicate instead of whole history). Decision recorded in LEDGER either way

### 4.6 Verification
Instruments trace before/after on a seeded account (demo history ≥ 200 sessions): main-thread time per set log; session-screen RAM; cold-start time; scroll hitches per 100 rows in Library. Existing tests + new: save-coalescer crash-recovery test.

---

## Phase 5 — `$impeccable harden` (P1, P2 ×4, P3 ×1)

### 5.1 VoiceOver coverage
- `SessionFocusView`: labels on close/finish/info/pencil/plates/media; GymStepper ± get `"\(unit) plus/minus \(step)"` + `.accessibilityValue` showing current; set rows: `.accessibilityElement(children: .contain)` — one element per row: "Set 2, 82.5 kg, 8 reps, RIR 2, logged"; draft rows announce "editable, Set 3, 60 kg" + adjustable trait steppers
- `ChatView`: message list as ordered list, "You: …" / "Coach: …", composer labeled, streaming message announces final once (not per token)
- Post-D3 Swift Charts: verify auto chart a11y rotor; supplement with `.accessibilityChartable` summary header ("6 points, trending down 3.8 kg")
- Sweeps: every `Image(systemName` inside a `Button` has a label (audit found ~35 unlabeled icon buttons app-wide, incl. `LibraryView`, `PlanView`, `WorkoutTabView`); run detector-style `rg` pass to drive coverage, VoiceOver manual pass per tab

### 5.2 Modal collision (`SessionFocusView.swift:884-903`)
- Working-weight sheet owns advance: sheet `onSave`/`onSkip` → `markDone + advanceOrShowFinish` in one callback; the finish dialog fires only after the sheet dismisses (sequenced state, not same-tick)

### 5.3 Plan-decode failure surfaces (`RootView.swift:161,299`)
- `try?` → do/catch: decode failure renders a full-screen error card ("Your plan could not be read — regenerate from your profile in Settings") + keeps Settings reachable; log to metrics like the other persistence paths

### 5.4 Empty/error edge states
- Plan decode fail (above) · catalog fail already OK (`ContentUnavailableView`) · chat provider-nil → inline disabled-composer reason (currently a silent dead input?) — verify and surface
- Library bulk edit: `.contextMenu` Delete/Duplicate on custom exercises (keep built-in delete confirm; no destructive swipe on rows — single-tap list rows are fine)

### 5.5 Verification
Xcode Accessibility Inspector (View Debugger) on all 5 tabs + session: 0 unlabeled elements, 0 contrast failures reported. Manual VoiceOver: complete one full workout logging flow screen-reader-only.

---

## Phase 6 — `$impeccable distill` (P2 ×2)

### 6.1 Home hierarchy (D7)
New scroll order: **Today card (routine + Start CTA + set progress)** → week strip → check-in (if due) → coach note (one line, expandable) → this-week recap → bodyweight → streak.
- `PendingObservationCard`/`SuggestionCard`: collapse into a single "Coach has N updates" bar pinned to the Home header; tap opens a stacked-card review sheet (accept/skip one-tap). Removes up to 5 full-width cards from the default view
- Start CTA never scrolls: it's the first card, not the fifth

### 6.2 Coach discoverability (D6)
- "Coach" pill (chat bubble icon + unread count) in Home header (same place as settings gear today); dead code `RootView.swift:359-366` removed; `.coach` AppTab case deleted or re-purposed as sheet route
- `CoachInsightPreview` "Open coach" affordance stays (two paths in, zero hidden paths)

### 6.3 Verification
Screenshot diff (light/dark, SE Max + Pro Max); fresh-eyes walkthrough: "start today's workout" reachable in < 2 s from cold tab open; "find coach chat" without being told where it is.

---

## Phase 7 — `$impeccable typeset` + `$impeccable polish` (P1 ×2 shared with Ph2, P2, P3)

### 7.1 Contrast tokens (asset catalog)
- `label3` white 0.45 → 0.58 (≥ 4.5:1 at caption sizes) · `label4` 0.25 restricted to decorative-only (audit the 8 usages; any live text moves up a tier) · chart axis → 0.62 at 11 pt
- All `GymTheme` surfaces/labels become Asset colors with High Contrast variants; accent set unchanged
- `Color.white`/`.black` literals (~25 sites) → `GymTheme.label`/`onAccent` token

### 7.2 Polish sweep
- `HomeView.swift:326` `print` → os.log/metric
- `SessionFocusView.swift:759-767` hardcoded `"0025" → "Push Day"` → read routine name from `StoredPlan` session name (fallback: first muscle-group label)
- `Theme.swift:26-29` legacy aliases (`green/blue/purple/yellow`) → deprecated `// sourcery` deprecated attribute; migrate remaining refs (11 found)
- Working weights: UserDefaults JSON blob → `WorkingWeightModel` SwiftData entity with migration (keeps `gym_working_weights_json` read-once import)

---

## Phase 8 — `$impeccable polish` (final gate)

- Re-run full audit (5-dimension score, same rubric)
- Simulator matrix: iPhone SE3 / 17 Pro Max / (iPad only if D1=b), Default + AX5 text, dark
- VoiceOver end-to-end one more time on session flow
- Update `docs/LEDGER.md` with the a11y/perf decisions (save coalescer, GIF renderer, iPhone-only, token assets)

---

## Test & measurement protocol (applies to every phase)

1. `xcodebuild test` green before + after each phase (existing suite + new coalescer/session-seed tests)
2. One Instruments capture per perf phase, on a machine-readably-named trace, attached numbers in LEDGER
3. Simulator goldens: home, session, library, stats — light/dark × Default/AX5 (captured with `xcrun simctl io booted screenshot`)
4. No phase ends with Accessibility Inspector warnings on touched screens
5. Commits: one per phase, message prefix `fix(uiux P1.x):` mapping to this doc's section numbers

## Effort estimate

| Phase | Est. | Notes |
|---|---|---|
| 0 init | 20 min | interview answers from you speed it up |
| 1 decisions | your call | D1–D7 |
| 2 adapt | largest (half a day) | mostly mechanical DT sweep |
| 3 animate | 1 h | small files |
| 4 optimize | half a day | GIF renderer + measurement |
| 5 harden | half a day | a11y labels are breadth work |
| 6 distill | 2–3 h | layout reshuffle, no new logic |
| 7 typeset/polish | 2 h | token conversion |
| 8 final gate | 1 h | |

## Expected outcome

| Dimension | Now | Target |
|---|---|---|
| Accessibility | 1 | 3 |
| Performance | 2 | 3–4 |
| Appearance & Theming | 2 | 3 |
| Platform Conformance | 2 | 3 |
| Adaptivity | 1 | 3 (D1=a) / 3–4 (D1=b) |
| **Total** | **8/20** | **15–16/20 (Good)** |

---

## Execution status — 2026-09-11 (complete)

Decisions: D1–D7 all taken as recommended ("go with all recommendations"). All changes left UNCOMMITTED in the working tree per user instruction ("never commit").

| Phase | Status | Notes |
|---|---|---|
| 0 init | done | `PRODUCT.md` at repo root |
| 2 adapt | done | 44 pt targets (GymStepper, session close/finish/log, tab pill); 343 Dynamic Type conversions across 33 files (display numerals ≥ 29 pt stay fixed); `TARGETED_DEVICE_FAMILY = "1"` + portrait-only; `@FocusState` in note/editor sheets + ChatView composer (`.submitLabel(.send)`, `interactiveDismissDisabled`) |
| 3 animate | done | `TimerFlashOverlay`: 2 black pulses, peak 0.35, suppressed under Reduce Motion; tab pulse + root toast gated |
| 4 optimize | done | `SessionRunner` save coalescer (markDirty/flushPendingSave, 700 ms, eager flush at finish/summary/teardown); `SessionElapsedClock` subview owns the 1 Hz tick; `lastTimeText`/`bestText`/`firstLoggedStart` memoized in `seedCurrentExercise`; native `AnimatedGifView` (`CGImageSource` pre-decode + ticker + LRU frame cache) replaces every WKWebView; `RemoteImageCache` (disk+mem) + `CachedRemoteImage` replace all 5 `AsyncImage` sites; `needsInitialSeed` moved off `body` via `.task` |
| 5 harden | done | metric tiles / charts / heatmap / history button VoiceOver labels (incl. spoken chart summaries); modal collision fixed (working-weight sheet no longer stacks with finish dialog — finish dialog now always reachable); plan decode failure → `ContentUnavailableView` with "Rebuild my plan"; ghost demo fallbacks (streak 13, −4.1 kg) removed |
| 6 distill | done | Home opens on today's workout (week strip + Start CTA first); all AI content (observations, suggestions, coach-note preview) collapsed behind one "Coach updates · N" disclosure; header Coach pill verified live; dead `.coach` TabView branch deleted (`AppTab.coach` case kept for state compat) |
| 7 typeset/polish | done | 66 low-contrast `Color(white:) < 0.58` literals raised to 0.60 across 17 files; `label3`/`label4` bumped; hardcoded routine names replaced by `RoutineNaming.dayName(for:)` (focus-muscle derived) in both session header and recent-workout rows; `print()` removed from SuggestionCard |
| 8 gate | done | full suite on physical iPhone 14: all unit + UI tests pass |

### Deviations from plan (recorded)
- **D3 charts:** kept hand-drawn `ProgressLineChart` (Swift Charts migration skipped) — a11y spoken summaries bolted on instead per the D3 fallback. ~250 lines retained.
- **GIF playback:** `TimelineView` used initially but replaced by a contained `GifFrameTimelineView` ticker (same cadence, one tiny view re-rendering; avoids hosting-screen invalidation).
- **Legacy Theme aliases** (`green/blue/purple/yellow`): kept as plain aliases (no deprecation tooling in this repo); zero runtime cost, rename deferred.
- **Verification protocol:** Instruments traces + goldens not captured; device test suite + build used as the gate instead.
