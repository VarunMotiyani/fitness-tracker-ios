# 01 — Brainstorm Summary

_Date: 2026-08-27_

A record of what was discussed and every decision made, with reasoning, so the
design docs can be understood in context.

## Classification

New project, nothing built → **architectural**. Full process: questions →
approaches → sectioned design → spec docs → implementation plan.

## Q&A and decisions

### Developer background

- Varun: **AI engineer, ~3 years' experience** — fluent in LLM APIs, structured
  output, prompt design, evaluation. Never built an iOS app; first time with
  Swift / SwiftUI / Xcode.
- **Decision:** keep v1 scope tight and native so it can actually be finished
  and installed on his own phone. Phased delivery, each phase usable. Docs
  assume LLM fluency; the learning curve is Apple platform mechanics only.

### Biggest source of friction

- Ranked: **"tell me exactly what to do today"** (primary), plus
  **accountability nudges** (secondary). Logging and nutrition are not the pain.
- **Decision:** core app = a structured plan that prescribes each session in
  detail + reminders to show up. Logging supports the plan; nutrition is out of
  v1.

### Gym / equipment

- Good commercial gym, but he wants to **declare the equipment himself**.
- Machines get occupied → he needs to flag it and get an **alternate exercise
  for the same muscle group** on the spot.
- Plan must be **history-aware** so each muscle group is targeted with the right
  volume across the week, and it **tracks his working weights**.
- **Decision:** a bundled, equipment-tagged **exercise catalog** is the
  backbone. Engine and swap feature only ever select from it.

### How the plan is generated

- Varun wants **AI** — "my own professional personal trainer" — but also said
  "it is rule based but it adapts to me."
- **Decision:** **hybrid (Approach A)**. A rule layer owns structure and safety
  (split templates, volume landmarks, load caps, injury exclusions). An AI layer
  personalizes within that skeleton (exercise selection from the available
  catalog, starting loads from history, sequencing, coaching notes) and adapts
  week to week and session to session. Rules clamp anything the AI returns.
- Cost concern addressed: BYO API key, ~a few cents to a couple dollars/month
  for one user. Not comparable to 2–3k/year subscriptions.

### Approaches considered

- **A — Coached engine (chosen).** Rule skeleton + AI personalization + rule
  clamps. Trainer feel with guardrails. Four usable phases.
- **B — AI-first, thin rules.** One big prompt does almost everything. Less code,
  faster start, but unpredictable, weak safety rails, more tokens, week-to-week
  drift. Rejected.
- **C — Rules-only now, AI in v2.** Lowest risk but explicitly not the app he
  described; the "adapts to me" feeling is his retention mechanism. Rejected.

### Fixed technical constraints (agreed)

- **No backend server.** All data on-device (SwiftData). AI calls go straight
  from app to model API with the user's key in Keychain. No hosting, no login,
  private.
- **Bundled exercise catalog** (~100–150 exercises from an open dataset with
  instruction images), tagged with primary/secondary muscles, required
  equipment, difficulty. Expandable (a ~800-exercise open dataset exists).

### Adaptation model

- Varun: gets a 4-day plan but often trains only 1–2 days; wants it to
  auto-adjust and understand. Wants to tell it "not energetic today" / "was able
  to lift today."
- **Decision:** a week is **a set of sessions to complete, not calendar days**.
  Three adaptation points:
  1. **Re-plan on demand** — every app open, completed volume vs. goals decides
     the next session; week rollover prioritizes undertrained groups. Nothing is
     "missed," it rebalances.
  2. **Pre-session check** — energy + time available → trim or boost the session.
  3. **Post-session feedback** — per-exercise easy/right/brutal + optional note →
     feeds progression math and a running niggle list.
- **Guardrails:** per-session load-increase cap; weekly per-muscle volume kept
  inside experience-appropriate min/max landmarks; injury flags force-exclude
  matching exercises; rest gap enforced between heavy sessions for the same
  muscle group.

### Training knowledge / "does it know the famous splits?"

- **Decision:** two layers.
  - The **AI model already knows the canon** (PPL, Arnold, Upper/Lower,
    PHUL/PHAT, bro split, full-body, 5/3/1, GZCLP, nSuns, 5×5, RPE programming,
    volume-landmark thinking, periodization).
  - The **app pins down** the parts that shouldn't rely on model memory:
    well-known split structures encoded as real **templates**; the **catalog**
    constrains exercise choice; **named programs**, if wanted, get hard-coded
    progression rules rather than regeneration.
- Varun's refinement: he wants **one engine that knows everything and just makes
  the plan and adapts** — he does not want to know or track any of it.
- **Decision:** **no program picker.** The user never chooses or names a split.
  Engine holds the knowledge, decides the structure, optionally shows a one-line
  "why this plan." Simpler, not more complex.

### Onboarding inputs (agreed)

Goal (one primary, weighted) · experience level · body stats (height, weight,
age, sex) · schedule capacity (sessions/week + session length, treated as a
ceiling not a commitment) · equipment checklist · limitations (injury/pain flags
+ hard "won't do" exercises). All editable; equipment/limitation changes trigger
a re-plan.

### InBody scan analysis (added by Varun)

- Monthly InBody scans. Wants to **upload the sheet photo**, have it
  **analysed**, and **update profile + workouts**. Sheet has PBF, SMM, protein,
  water, etc.
- **Decision:** vision-model extraction → weight, PBF %, SMM, BMR, total body
  water, protein mass, mineral, visceral fat level, InBody score, segmental lean
  analysis (L/R arm, trunk, L/R leg), scan date. **User confirms numbers** on a
  review screen before save. Stored as a **time series** → trend view. Feeds
  engine: stalled SMM despite consistency → recovery/volume adjustment +
  nutrition flag; segmental imbalance → bias unilateral work. Deep segmental
  programming is a later refinement.

### In-gym session flow (agreed)

Start → energy + time questions → engine finalizes today's session. One exercise
at a time: name, target sets×reps, target weight (last logged + progression
rule), instruction image + cues. Log sets with pre-filled targets, auto rest
timer. Per-exercise feedback. **Swap** = one tap → 2–3 same-primary-muscle
alternatives from owned (likely-free) equipment in the same rep range; target
weight carries over adjusted; swap remembered for the session only. Finish →
summary (volume vs target, PRs) → writes history + updates rolling week.
Abandoning mid-session is fine; logged work counts, remainder flows back into the
week.

### Feedback loop horizons (agreed)

- **Next session:** logged weights become baselines; easy → load up (within cap);
  brutal/missed → hold or back off; niggle note → deprioritize/swap that
  exercise + add to limitations list; repeated manual swaps → engine changes its
  default.
- **Rest of week:** completed vs. goal volume decides next session emphasis.
- **Next week:** undertrained groups prioritized; broad progress → advance whole
  plan; many "brutal" + stalls → lighter deload-style week.
- **Monthly:** InBody trend is the long-range check.

### AI contract & failure handling (agreed)

- Every AI call = structured request → **structured JSON** response. Calls:
  weekly plan generation, session finalization, swap, InBody extraction.
- **Provider (updated):** not Anthropic, but **nothing committed** — selection is
  deferred research on reasoning quality + latency + cost per call. A fully
  provider-agnostic `LLMProvider` protocol (`complete` + `completeWithImage`)
  that Gemini / OpenAI / Anthropic / a router / a local model can each implement;
  one schema definition per call, each adapter maps it to the provider's native
  structured-output mechanism; `provider` + `modelName` + per-token pricing are
  settings. Phase 1 builds one provisional adapter to develop against only.
- **Validation layer** on every response: exercise IDs exist in catalog; load
  jumps within cap; weekly volume within landmarks; excluded exercises absent.
  Fail → one auto-retry with errors fed back → still failing → **fall back to
  rule engine alone** (templates + last week progressed by the simple rule).
- **Failure states:** no API key → onboarding blocks with a link, rest of app
  works; offline → current week/session cached, training + logging fully work,
  regeneration queues; API error/timeout/rate-limit → one retry → rule-engine
  fallback + quiet notice, logs always saved locally first; bad InBody photo →
  low confidence → manual entry screen.
- **Cost visibility:** running month-to-date API spend estimate in settings.

### Notifications (agreed)

Local only (no server): session reminders (adjustable, snoozable); nudge if no
training in X days with unmet weekly volume; monthly InBody reminder; rest-timer
alerts. All toggleable; not guilt-heavy by default.

### Tech stack (agreed)

SwiftUI, iOS 17+, iPhone only · SwiftData (profile, history, InBody series,
catalog, cached plans) · Keychain (API key) · direct HTTPS to the LLM provider
(`LLMProvider` protocol, concrete provider/model TBD), no backend · bundled JSON
catalog + images · UserNotifications.

### Native Swift vs React Native (decided: native Swift/SwiftUI)

- **Considered:** React Native / Expo — attractive if the user already had deep
  RN muscle, since it would speed the language ramp.
- **Decision: native Swift/SwiftUI.** Reasons:
  - Zero cross-platform payoff — one user, one iPhone; RN's whole value prop is
    unused.
  - On-device inference (Apple Foundation Models) is Swift-only — it's the
    zero-cost model path once the user is on Apple-Intelligence hardware.
  - HealthKit, local notifications, camera (InBody), SwiftData all first-class
    in Swift, all friction in RN.
  - Keeps a future watchOS app (wrist-during-workout: current set / target /
    rest timer / live HR) possible with no rewrite — RN cannot build watchOS.
  - Form-heavy + list-heavy UI is SwiftUI's sweet spot.
  - LLM calls are plain HTTPS — no advantage to RN there.
- **Note:** reading Watch data (post-session HR/calories via HealthKit) does NOT
  require a watchOS app; that's a phone-app feature, deferred to Phase 4. The
  watchOS app itself is "Later".

### Testing approach (agreed)

Heavy unit coverage on rule engine + validation layer (safety-critical) · AI
response handling tested with recorded/mocked JSON (valid, malformed, bad ID,
unsafe jump) · InBody extraction with mocked vision responses + a few real
photos by hand · SwiftData round-trip tests · manual acceptance = real sessions
in his gym.

## Deliverable of this brainstorm

This set of markdown docs (`00`–`05`), then an implementation plan via the
writing-plans skill.
