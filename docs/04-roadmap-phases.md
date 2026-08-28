# 04 — Roadmap & Phases

_Date: 2026-08-27_

Four phases. **Each phase is usable on its own** — the point is that this project
never becomes the same overwhelm spiral that ended the gym habit. Ship phase 1,
use it, then build phase 2.

Guiding rule: don't start a phase until the previous one runs on Varun's phone.

---

## Phase 1 — "Give me a plan"

> **Split during execution into 1a / 1b / 1c** (see `HANDOFF.md` for the current
> breakdown and status). **Phase 1 is complete.**
> - **1a ✅ merged** — `FitnessCore` Swift package (domain, catalog, rule engine,
>   validation, `LLMProvider` contract). 35 tests.
> - **1b ✅ merged** — `FitnessTracker` app: onboarding →
>   rule-engine plan → read-only plan view, offline, no AI. SwiftData persistence,
>   Settings scaffold. 12 app unit tests.
> - **1c ✅ complete** (branch `phase-1c-ai-integration`, pending merge) — AI
>   integration: 3 `LLMProvider` adapters (`openAICompatible`, `gemini`,
>   `appleOnDevice`) + `LLMProviderFactory`, user-managed `ProviderProfile`s with
>   Keychain-stored keys, `PlanCoordinator` (generate → validate → retry-once →
>   rule fallback, `WeeklyPlan.source` tracked), `AICallRecord` cost ledger +
>   `CostSummary`, `$` chip / Usage section / post-generation note, provider-profile
>   UI. Deferred (documented): budget cap + `pauseAIWhenOverBudget`, native
>   Anthropic / Gemini-Vertex / AWS-Bedrock adapters, vision. The "Build" list
>   below from `ProviderProfile` / `AICallRecord` / cost onward was 1c.

**Goal (met):** open the app, answer onboarding, get a real weekly plan you can read.

**Built:**
- SwiftData models (profile, equipment, limitations, weekly plan,
  `ProviderProfile`, `AICallRecord`).
- Onboarding flow (all fields from §2 of product design).
- Bundled exercise catalog (~100–150 exercises + images) + `CatalogStore`.
- `RuleEngine`: split templates + volume landmarks (progression can be stubbed).
- `LLMProvider` protocol + **three adapters shipped** (`openAICompatible`,
  `gemini`, `appleOnDevice`; native `anthropic` / Vertex / Bedrock deferred —
  `openAICompatible` reaches them via compat/proxy endpoints) against
  user-managed `ProviderProfile`s (no seeded profile — rule engine until the
  user adds one) + `LLMProviderFactory` + `WeeklyPlanDTO` JSON decode.
- `Validator`: catalog-id + exclusion + volume-band checks.
- `PlanCoordinator`: generate → validate → retry-once → rule-engine fallback.
- Plan view: read-only week, sessions, exercises, targets, "why this plan" —
  reads from SwiftData, works offline.
- **Cost metering:** `AICallRecord` written per call, `costUSD` from the active
  profile's prices, after-generation one-liner, month-to-date `$` chip on the
  Plan screen.
- Settings: manage provider profiles (add/edit/activate, paste key to Keychain,
  set model ID + prices); basic month-to-date + all-time cost totals.

**Done when (met):** onboarding → a validated, sensible weekly plan appears; a
forced AI failure still produces a fallback plan; each generation shows its cost
and the month-to-date figure updates; switching the active provider profile takes
effect on the next call.

**Not in Phase 1:** logging, session runner, swaps, InBody, notifications, the
full Usage & Cost screen, budget cap.

---

## Phase 2 — "Run my session and remember it"

**Goal:** train from the app and build history.

**Build:**
- Session runner UI: one exercise at a time, instruction images + cues.
- Set logging (reps + weight, pre-filled targets), auto rest timer.
- Pre-session check (energy + time) → `AIClient` session finalization call.
- Per-exercise feedback (easy / right / brutal + note); overall session note.
- `CompletedSession` / `CompletedEntry` / `LoggedSet` persistence.
- Session summary (volume vs target, PRs).
- Abandon-mid-session handling.
- History view: past sessions, per-exercise weight progression.
- `RuleEngine` progression rule now real; feeds next session's target loads.

**Done when:** Varun can do a full gym session from the app, and last week's
weights show up as this week's targets.

---

## Phase 3 — "Adapt to what actually happened"

**Goal:** the rolling plan and the swap feature.

**Build:**
- Rolling re-plan on app open: completed vs. goal volume → next session emphasis.
- Week rollover: undertrained muscle groups prioritized.
- Machine-occupied **Swap**: `RuleEngine` swap search + `AIClient` swap call,
  2–3 candidates, target carried over, session-only.
- Repeated-manual-swap → engine default shift.
- Weekly adaptation: broad progress → advance plan; many "brutal" + stalls →
  lighter deload-style week.
- Niggle list surfaced into plan generation.
- Rest-gap check enforced.

**Done when:** skipping two sessions visibly rebalances the next plan with zero
configuration, and Swap keeps a session moving in one tap.

---

## Phase 4 — "InBody + nudges + polish"

**Goal:** the long-range signal and staying-on-track.

**Build:**
- InBody photo upload → `InBodyExtractor` (vision) → confirm screen → save.
- InBody time series + trend view (PBF, SMM, weight over months).
- Engine signals from InBody: stalled SMM → recovery/volume + nutrition flag;
  segmental imbalance → bias unilateral work.
- Local notifications: session reminders, inactivity nudge, monthly InBody
  reminder, rest-timer alerts. All toggleable.
- **Full Settings → Usage & Cost screen:** breakdown by call type, 30-day
  sparkline, call count + average, editable price fields per profile.
- **Budget cap:** optional `monthlyBudgetUSD`, 80% / 100% warning banners, and
  the `pauseAIWhenOverBudget` toggle (100% → rule-engine-only until rollover).
- Polish: empty states, error copy, offline indicator, first-run guidance.

**Done when:** monthly scan upload takes seconds, produces a readable trend,
notifications behave, and the cost screen + budget toggle work end to end.

---

## Later (post-v1, explicitly deferred)

- Apple Watch companion (live logging, heart rate, rings).
- HealthKit / Apple Health sync.
- iCloud multi-device sync (CloudKit).
- Light nutrition layer: protein target readout, not full calorie tracking.
- Faithful named-program mode (hard-coded 5/3/1 etc.).
- Deeper segmental-imbalance programming.
- Catalog expansion toward the full ~873-exercise `free-exercise-db` set; and/or
  a paid animated-media layer (GymVisual-class GIFs) swapped in behind the
  existing `Exercise` schema.

---

## Dependency sketch

```
Phase 1 ──► Phase 2 ──► Phase 3
                  └────► Phase 4 (InBody/notifications don't depend on Phase 3)
```

Phase 4 can start after Phase 2 if adaptation (Phase 3) is taking longer than
expected — InBody ingestion and notifications are independent of the rolling
re-plan.
