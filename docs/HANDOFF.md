# HANDOFF — Read This First

_Living document. Last updated: 2026-08-28._

**Purpose:** one read = full context. If you're a new agent/session on any
device, read this top to bottom before doing anything. It captures the project,
every decision, current state, how to work here, and what's next. Deep detail
lives in the numbered docs; this is the index + digest.

**Update policy:** refresh this doc at every **major** step — a decision made or
reversed, a phase started/finished, scope changed, a new doc added,
provider/model chosen, repo/workflow change — or whenever the user asks. Not for
minor edits or exploratory work. Bump "Last updated" when you do.

---

## 1. What the project is

A **personal iOS app** for one user (Varun, 24) that acts as an adaptive
strength & physique coach. Varun is an **AI engineer (~3 yrs)**; this is his
**first iOS app**. He got into the gym Nov 2024 as a first-timer, lost ~8–9 kg
with ChatGPT-driven structure, then quit — the failure mode was **decision/
research overload**, not the training. The app removes "what do I do today":

- Equipment-aware **weekly plan** — user declares gym equipment; every exercise
  and substitution comes only from that pool.
- Tells him exactly what to do each session (exercise, machine, sets, reps,
  target weight) with instruction visuals — walk in and follow it.
- **Rolling adaptation**: a week is a *set of sessions to complete, not calendar
  days*. Recomputed from real history on every app open. Adapts to skipped
  sessions, "low energy today", "felt strong", and logged performance.
- **One-tap machine swap** → equivalent exercise for the same muscle group.
- **Monthly InBody scan** photo → vision extraction → trend tracking → feeds the
  planner.
- Local reminders to show up.

Not a product for distribution. That's why every technical choice favours
simplicity: no backend, no accounts, on-device storage, bring-your-own API key.

---

## 2. Current status

| | |
|---|---|
| **Phase** | Design complete. **Phase 1a plan written**, not yet executed. No code yet. |
| **Next action** | Execute `docs/superpowers/plans/2026-08-28-phase-1a-fitnesscore-foundation.md` (14 TDD tasks) via `superpowers:subagent-driven-development` or `executing-plans`. |
| **Phase 1 split** | **1a** `FitnessCore` package (pure Swift, no Xcode needed) → **1b** app shell + SwiftData + onboarding + plan view (needs Xcode) → **1c** LLM adapters + `PlanCoordinator` + cost metering. |
| **Repo** | `github.com/VarunMotiyani/fitness-tracker-ios` (public) |
| **Branch** | `main` |
| **Uncommitted** | Check `git status` — doc edits are often pending; the user controls when they're committed. |

---

## 3. The docs (what's where)

| Doc | Contents |
|-----|----------|
| **HANDOFF.md** (this) | Entry point / full digest |
| [00-overview.md](00-overview.md) | Problem, vision, goals/non-goals, builder & provider context, success criteria |
| [01-brainstorm-summary.md](01-brainstorm-summary.md) | Every Q&A of the design conversation + reasoning behind each decision |
| [02-product-design.md](02-product-design.md) | Behaviour: adaptation model, onboarding, InBody, session flow, feedback loop, notifications, **§9 model/cost/offline**, scope |
| [03-technical-architecture.md](03-technical-architecture.md) | Stack, module boundaries, **full SwiftData data model**, catalog, rule engine, **§6 AI contract + LLMProvider**, **§6.5 token estimate**, validation, **§8 failure handling + §8.1 cost tracking**, testing, **§10 project structure** |
| [04-roadmap-phases.md](04-roadmap-phases.md) | 4 phases, each independently usable, with "done when" criteria |
| [05-open-questions.md](05-open-questions.md) | Undecided items (resolved ones struck through) |
| [06-decisions.md](06-decisions.md) | **Terse decision register** — every settled choice in tables (P/A/C/D/R groups) |
| [07-exercise-dataset-research.md](07-exercise-dataset-research.md) | Web research: exercise datasets compared, why `free-exercise-db` won |
| [08-api-cost-analysis.md](08-api-cost-analysis.md) | LLM cost modelling by model class, levers, scenarios |
| [09-tooling-skills-plugins.md](09-tooling-skills-plugins.md) | Claude Code skills/plugins to use, install, and build custom |
| [superpowers/plans/](superpowers/plans/) | Implementation plans. **1a** = `2026-08-28-phase-1a-fitnesscore-foundation.md` (14 TDD tasks, no Xcode needed). |

---

## 4. Key decisions (digest — full register in [06](06-decisions.md))

### Product
- **Hybrid coaching engine**: rule skeleton + AI personalization + rule clamps
  (rejected AI-first as unpredictable, rules-only as losing the "adapts to me"
  feel).
- **No program picker.** User never names/manages a split; the engine decides,
  may show a one-line "why".
- Week = set of sessions, not calendar days; re-planned from history on every
  open.
- Three adaptation points: re-plan on open · pre-session energy/time check ·
  post-session easy/right/brutal feedback + niggle notes.
- Guardrails (rule layer): per-session load cap · weekly volume kept inside
  landmark band · injury flags force-exclude exercises · rest gap between heavy
  same-muscle sessions.
- InBody: photo → vision extract → **user confirms numbers** → time series +
  trend → feeds engine (stalled SMM → recovery/volume + nutrition flag;
  segmental imbalance → bias unilateral).
- v1 **excludes**: food/macro tracking, Apple Watch app, HealthKit sync, iCloud
  sync, social, video content, multi-user.

### Architecture
- **Native Swift / SwiftUI**, iPhone only. Not React Native (no cross-platform
  payoff for one user; on-device inference & Apple integrations are Swift-only;
  keeps a future watchOS app possible with no rewrite).
- **No backend.** All data on-device via **SwiftData**. AI calls go straight
  from app to provider with the user's key in **Keychain**.
- **Min deployment target: iOS 26** (user's iPhone 14 runs iOS 26).
- **Project structure:** Xcode app target **+ local `FitnessCore` Swift package**
  (RuleEngine, Validator, Catalog, LLM protocol) with no Apple-UI deps → fast
  unit tests without a simulator.
- **AI layer:** provider-agnostic `LLMProvider` protocol (`complete` +
  `completeWithImage`). **Four adapters ship**: `openAICompatible`, `gemini`,
  `anthropic`, `appleOnDevice`.
- **User-managed `ProviderProfile`s** — the active model is a runtime-editable
  profile (name, adapterKind, baseURL, key, modelID, vision flag, per-token
  prices), NOT a build constant. New vendor/model = add/edit a profile, no app
  update. `openAICompatible` covers most future vendors.
- **Concrete provider/model is NOT chosen** — deferred research. Criteria:
  reasoning quality, latency, cost/call. Phase 1 seeds one provisional profile
  (whatever's fastest to stand up). See [08](08-api-cost-analysis.md).
- Consumer subscriptions (Gemini Pro, ChatGPT Go/Plus) **cannot** be used — no
  API access. Free paths: Gemini API free tier, or on-device Foundation Models
  (needs Apple-Intelligence hardware — NOT the iPhone 14; OK on a future 17 Pro).
- **Validation layer** on every AI response (catalog-id, exclusions, load cap,
  volume band, rest-gap, JSON decode) → fail → retry once with errors → fall
  back to rule engine alone. User always gets a workout.
- **Real-time cost metering**: one `AICallRecord` per call, `costUSD` from the
  active profile's prices (frozen at write time). Always-visible month-to-date
  `$` chip + after-generation one-liner (Phase 1); full Usage & Cost screen +
  breakdown + sparkline (Phase 4).
- **Budget**: optional `monthlyBudgetUSD`, 80%/100% warnings, `pauseAIWhenOver
  Budget` toggle (default off) → at 100% switch to rule-engine-only until
  rollover.
- **Offline**: active plan + sessions in SwiftData → browse/run/log/manual-swap
  all work offline; only generation/adjust/AI-swap need network (they queue).

### Content
- **Exercise catalog base = `yuhonas/free-exercise-db`** — ~873 exercises,
  **Unlicense (public domain)**, static start/end JPGs. Most comprehensive
  dataset that's genuinely free to bundle. Bigger animated-GIF sets (ExerciseDB
  API ~$10–50+/mo, `hasaneyldrm`, MuscleWiki) are commercial/GymVisual media —
  rejected; parked as a future one-time-licence **media-layer swap** (the
  `Exercise` schema separates media refs from data for exactly this).
- v1 catalog = curated **~100–150-exercise subset** remapped to the app's own
  `Exercise` schema. Exact list TBD from Varun's equipment checklist.
- `wger` (CC-BY-SA) is an attribution-required gap-filler if needed.
- **Volume landmarks** seeded from **Renaissance Periodization MEV/MAV/MRV**
  (weekly working-set counts per muscle × experience), stored as a config table,
  tuned later from real logs. Purely a clamp on the AI.
- Split templates encoded explicitly: full body, upper/lower, PPL, Arnold.

### Delivery
- **4 phases**, each independently usable:
  1. **Give me a plan** — models, onboarding, catalog, rule-engine
     templates+landmarks, 4 LLM adapters + provisional profile, generation →
     validation → fallback, cost metering + `$` chip, read-only plan view,
     Settings (profile management), offline plan reads.
  2. **Run my session & remember it** — session runner, set logging, rest timer,
     pre-session check, feedback, history, real progression rule.
  3. **Adapt to what happened** — rolling re-plan, week rollover, machine-occupied
     swap (rule + AI), weekly adaptation / deload.
  4. **InBody + nudges + polish** — scan ingestion + trend, engine signals from
     InBody, local notifications, full Usage & Cost screen + budget cap, polish.
- Don't start a phase until the previous runs on Varun's phone. Phase 4 may start
  after Phase 2 if Phase 3 slips.
- **Testing:** heavy unit coverage on RuleEngine + Validator (safety-critical);
  mocked JSON for AI handling; recorded HTTP fixtures per adapter; cost-ledger
  tests; mocked vision + real photos for InBody; SwiftData round-trip; manual
  acceptance = real gym sessions.

---

## 5. Still open (non-blocking — see [05](05-open-questions.md))

Curation list (needs equipment checklist) · image size budget · load estimation
for brand-new lifts · progression cap numbers · deload trigger specifics ·
**provider/model selection** · history window size · prompt storage (code vs
bundled file) · `LLMProvider` surface confirmation · InBody sheet-format
variance & sample photos · confidence threshold for manual entry · **app name**
(placeholder "Fitness Tracker") · onboarding "won't do" list UX · notification
defaults.

---

## 6. How to work on this project

### Git — IMPORTANT
- **Never `git commit` or `git push` without the user explicitly asking, every
  time.** Prior approval does not carry forward. Make/save file edits freely,
  then stop and report what's ready.
- **No `Co-Authored-By` trailer** in commit messages (overrides global CLAUDE.md).
- Repo: `github.com/VarunMotiyani/fitness-tracker-ios`. Machine-specific auth
  setup (SSH keys, which GitHub account is default) is not documented here on
  purpose — it varies by device. If a push fails, sort out credentials on that
  machine; don't assume a particular account.

### Environment
- iPhone 14 on **iOS 26**, Apple Watch Series 10, iPhone 17 Pro planned.

### Skills / plugins (see [09](09-tooling-skills-plugins.md) for the full list)
- **Use now:** `superpowers:writing-plans` (next), `test-driven-development`,
  `executing-plans`, `systematic-debugging`, `using-git-worktrees`,
  `requesting-code-review`, `/security-review`, `claude-api` (for the AI layer).
- **Install for the build:** XcodeBuildMCP (or Xcode 26.3+ built-in MCP) ·
  `build-ios-apps` plugin · one SwiftUI skill pack (`dpearson2699/swift-ios-skills`
  recommended).
- **Build later (after Phase 1):** custom `fitness-core-conventions`,
  `catalog-curation`, `phase-workflow` skills.
- **Ignore:** all web-UI design skills, `python-pytest-ops`, `loop`, `schedule`.

### Process
Architectural brainstorm is **done**. The only next skill is
`superpowers:writing-plans` → Phase 1 plan → then `executing-plans` /
`subagent-driven-development` with review checkpoints. TDD throughout, especially
RuleEngine + Validator.

---

## 7. How we got here (chronology)

1. Brainstormed the idea end-to-end (classified architectural; full Q&A).
2. Chose the hybrid engine (Approach A) over AI-first / rules-only.
3. Settled: no program picker, rolling plan, three adaptation points, guardrails.
4. Added InBody scan analysis as a feature.
5. Confirmed builder context (AI engineer, first iOS app) and that consumer
   LLM subscriptions can't be used.
6. Wrote docs 00–05.
7. `git init`, first commit, pushed to the public repo.
8. Resolved open questions: `free-exercise-db` (web research → doc 07), RP volume
   landmarks, Xcode app + `FitnessCore` package, iOS 26 target.
9. Chose native Swift over React Native.
10. Added decision register (doc 06).
11. Added API cost analysis (doc 08) after a token-volume estimate.
12. Expanded the AI layer: user-managed `ProviderProfile`s, four adapters,
    real-time cost metering, budget toggle, explicit offline guarantee.
13. Researched skills/plugins (doc 09).
14. Wrote this handoff doc.
15. Split Phase 1 into 1a/1b/1c. Wrote the **Phase 1a** plan (`FitnessCore`
    package, 14 TDD tasks) via `superpowers:writing-plans`.

---

## 8. Gotchas for a fresh agent

- **No code exists.** Don't look for a Swift project — it's docs only.
- **Provider/model is deliberately unchosen.** Don't hardcode Gemini/OpenAI/
  Anthropic anywhere; everything routes through `LLMProvider` + `ProviderProfile`.
- **iPhone 14 is on iOS 26** but does **not** support Apple Intelligence →
  on-device Foundation Models isn't available until the 17 Pro. Min target is
  still iOS 26.
- **Don't commit/push** unless asked in that turn.
- The catalog's media is **static images**, not GIFs — by necessity (licensing),
  with a documented paid-upgrade path.
- `FitnessCore` package must stay **UI-framework-free** so it tests fast.
