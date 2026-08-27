# 06 — Decision Register

_Started: 2026-08-27_

Every settled decision, terse, in one place. Rationale lives in
[01-brainstorm-summary.md](01-brainstorm-summary.md); this is the quick-reference
index. Newest decisions at the bottom of each group.

Status: **Settled** unless marked **Provisional** (holds until revisited) or
**Deferred** (tracked in [05-open-questions.md](05-open-questions.md)).

---

## Product

| # | Decision | Status | Notes |
|---|----------|--------|-------|
| P1 | The app is a personal, single-user iOS tool for Varun — not a distributed product | Settled | Drives every "simplest thing" call |
| P2 | Core value = eliminate per-session decision-making: open app → told exactly what to do → do it | Settled | The retention mechanism |
| P3 | **Hybrid coaching engine** (Approach A): rule skeleton + AI personalization + rule clamps | Settled | Rejected AI-first (unpredictable) and rules-only (loses the "adapts to me" feel) |
| P4 | **No program picker.** User never names or manages a split; the engine decides and may show a one-line "why" | Settled | |
| P5 | A week is **a set of sessions to complete, not calendar days**; plan recomputed from real history on every app open | Settled | |
| P6 | Three adaptation points: re-plan on open, pre-session energy/time check, post-session feedback | Settled | |
| P7 | Guardrails: per-session load cap, weekly volume kept in landmark band, injury flags force-exclude, rest gap between heavy same-muscle sessions | Settled | |
| P8 | **InBody scan** ingestion: photo → vision extraction → user confirms numbers → time series + trend → feeds engine | Settled | Deep segmental programming deferred |
| P9 | Notifications: **local only**, all toggleable, not guilt-heavy | Settled | |
| P10 | v1 excludes: food/macro tracking, Apple Watch app, HealthKit sync, iCloud sync, social, video content, multi-user | Settled | Reading Watch data via HealthKit is a Phase 4 phone-app feature, not a watchOS app |
| P11 | App name | Deferred | "Fitness Tracker" is a placeholder (Q13) |

## Architecture

| # | Decision | Status | Notes |
|---|----------|--------|-------|
| A1 | **Native Swift / SwiftUI** — not React Native | Settled | No cross-platform payoff; on-device inference is Swift-only; Apple integrations first-class; keeps future watchOS app possible with no rewrite |
| A2 | **No backend server.** All data on-device via **SwiftData** | Settled | |
| A3 | **Bring-your-own API key**, stored in **Keychain** | Settled | |
| A4 | AI access via a **provider-agnostic `LLMProvider` protocol** (`complete` + `completeWithImage`) | Settled | |
| A5 | Concrete LLM provider + model | Deferred | Criteria: reasoning quality, latency, cost/call. Candidates: Gemini Flash-class, GPT-mini-class, Claude Haiku-class, router, local. Build one provisional adapter in Phase 1 (Q8) |
| A6 | Consumer chat subscriptions (Gemini Pro, ChatGPT Go/Plus) **cannot** be used — no API access. Free paths: Gemini API free tier, or on-device Foundation Models (needs Apple-Intelligence hardware) | Settled | |
| A7 | **Validation layer** on every AI response; fail → retry once with errors → fall back to rule engine alone | Settled | User always gets a workout |
| A8 | Every AI call is **structured request → structured JSON** (schema-constrained), never loose prose | Settled | |
| A9 | **Min deployment target: iOS 26** | Settled | Varun's iPhone 14 runs iOS 26; no reason to support older (Q18) |
| A10 | **Project structure:** Xcode app target + local **`FitnessCore` Swift package** (RuleEngine, Validator, Catalog, LLM protocol) with no Apple-UI deps | Settled | Fast unit tests without a simulator (Q17) |
| A11 | Cost meter: accumulate token usage into `monthToDateTokenCost`, shown in Settings, reset monthly; per-token price stored in settings | Settled | Maintenance approach is Q20 |

## Content / data

| # | Decision | Status | Notes |
|---|----------|--------|-------|
| C1 | **Exercise catalog base = `yuhonas/free-exercise-db`** — ~873 exercises, Unlicense (public domain), static start/end JPGs | Settled | Most comprehensive dataset that is genuinely free to download & bundle. Full comparison: [07-exercise-dataset-research.md](07-exercise-dataset-research.md) |
| C2 | Bigger datasets rejected: **ExerciseDB** = paid hosted API (~$10–50+/mo), API-access/hotlink model, needs a backend, can't bundle offline; **`hasaneyldrm`** / **MuscleWiki** = proprietary GymVisual-class media needing a paid licence | Settled | Animated media parked as a later one-time-licence media-layer upgrade, not an API subscription |
| C3 | `wger` (CC-BY-SA) is the attribution-required **gap-filler** if the subset has holes | Provisional | Use only if needed |
| C4 | v1 catalog = curated **~100–150-exercise subset** remapped to the app's own `Exercise` schema | Settled | Exact list is Q2, needs Varun's equipment checklist |
| C5 | **Media layer is swappable** — `Exercise` schema separates media refs from exercise data, so paid animated media can drop in later without touching logic | Settled | |
| C6 | **Volume landmarks** = weekly working-set table per muscle × experience, seeded from **Renaissance Periodization MEV/MAV/MRV**, stored as config, tuned from real logs | Settled | Purely a clamp on the AI (Q4) |
| C7 | Split templates encoded explicitly: full body, upper/lower, PPL, Arnold | Settled | |
| C8 | Load estimation for brand-new lifts; progression caps; deload trigger | Deferred | Q5, Q6, Q7 — first-pass numbers during Phase 2/3 |

## Delivery

| # | Decision | Status | Notes |
|---|----------|--------|-------|
| D1 | **Four phases**, each independently usable: (1) plan generation, (2) session runner + history, (3) rolling adaptation + swaps, (4) InBody + notifications + polish | Settled | See [04-roadmap-phases.md](04-roadmap-phases.md) |
| D2 | Don't start a phase until the previous one runs on Varun's phone | Settled | |
| D3 | Phase 4 may start after Phase 2 if Phase 3 slips (InBody + notifications are independent of rolling re-plan) | Settled | |
| D4 | Testing: heavy unit coverage on RuleEngine + Validator; mocked JSON for AI handling; mocked vision + real photos for InBody; SwiftData round-trip; manual acceptance = real gym sessions | Settled | |
