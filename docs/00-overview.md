# 00 — Overview

_Date: 2026-08-27_

## The problem

Varun, 24, started going to the gym in November 2024 as a complete first-timer at
84 kg. It went well for ~2 months with a trainer covering the basics. The trainer
then pushed hard to be hired as a paid personal trainer, which was too expensive.
Varun switched to self-directed training: his own research, YouTube, ChatGPT.

That worked for weight loss — he lost ~8–9 kg driving a calorie deficit with
ChatGPT-structured guidance — but the **decision and research load became
overwhelming**. Every session turned into "what do I even do today," the friction
compounded, and he stopped going and returned to a sedentary routine.

He looked at commercial workout apps. They cost ~2–3k/year, and even then they
don't do what he actually wants.

### The real failure mode

He doesn't quit because training is hard. He quits because **planning and
deciding** is a constant, open-ended tax on every session. Remove "what do I do
today" and he has already shown he executes: 2 months with a trainer, 8–9 kg lost
with ChatGPT holding the structure.

## The vision

One app on his iPhone that is, in effect, **his own professional personal
trainer**:

- Builds a weekly training plan from established training knowledge — he never
  picks or names a split.
- Tells him exactly what to do each session: which exercise, which machine, sets,
  reps, target weight, with instruction visuals, so he walks in and follows it.
- Is **equipment-aware**: he declares what his gym has; every suggestion and
  substitution comes only from that.
- Handles **machine-occupied** situations: one tap gives an equivalent exercise
  for the same muscle group.
- **Adapts continuously**: to sessions he skipped, to "no energy today," to "felt
  strong today," to what he actually lifted. The plan is recomputed from real
  history every time he opens the app.
- **Reads his monthly InBody scans** from a photo, tracks PBF / SMM / etc. over
  time, and uses the trend as the long-range signal for whether the plan works.
- Nudges him to show up.

## Who it's for

One user, one iPhone (currently iPhone 14; iPhone 17 Pro planned). Apple Watch
Series 10 owned. Mac available for development. Not a product for distribution —
a personal tool. That shapes every technical decision toward simplicity: no
backend, no accounts, no hosting, bring-your-own API key.

## Builder context

Varun is an **AI engineer with ~3 years' experience** — comfortable with LLM APIs,
structured output, prompt design, and evaluation. The unfamiliar part is **iOS
itself**: this is his first Swift / SwiftUI / Xcode app. So the docs assume LLM
fluency and don't explain AI concepts; the learning curve is Apple platform
mechanics, not the model layer.

## Model provider

**Undecided — deferred to later research.** The selection criteria are: strong
reasoning/instruction-following, low latency, and low overall cost per call
(these calls are frequent — weekly plans, per-session finalization, swaps). Most
likely a "fast/cheap/smart" tier (Gemini Flash-class, GPT-mini-class, or
equivalent), possibly routed through an aggregator, but nothing is committed.

The AI layer is therefore **fully provider-agnostic**: an `LLMProvider` protocol
that any of Gemini / OpenAI / Anthropic / OpenRouter-style routers / a local
model can implement. `provider` and `modelName` are runtime config, not
compile-time assumptions. Structured output is expressed once as a JSON schema
and each adapter maps it to that provider's native mechanism (`responseSchema`,
`response_format`, tool-use, etc.). One provisional adapter is built in Phase 1
purely to develop against; the real choice is a config change, no code change in
the app's logic layers.

## Goals

1. Eliminate per-session decision-making. Open app → told what to do → do it.
2. Plans grounded in real training principles, not improvised each week.
3. Genuinely adaptive — around missed sessions, daily readiness, and logged
   performance.
4. Equipment-aware prescriptions and on-the-fly substitutions.
5. InBody scan ingestion via photo, with trend tracking that feeds the planner.
6. Cheap to run: a few cents to a couple dollars a month on the user's own API
   key. No subscription.
7. Finishable as a first real iOS app — tight scope, phased delivery, each phase
   usable on its own.

## Non-goals (v1)

- Food / calorie / macro tracking (use a dedicated app; a light protein-target
  readout may come later).
- Apple Watch companion app.
- HealthKit / Apple Health sync.
- iCloud multi-device sync (easy to add later; single phone for now).
- Social, sharing, community features.
- Video exercise content (images + form cues only).
- Multi-user support, onboarding for anyone but Varun.
- A program picker / named-program management UI. The engine decides; the user
  doesn't manage it.

## Success criteria

- Varun opens the app before a session and is training within ~30 seconds, with
  no thinking required about what to do.
- When a machine is taken, the swap takes one tap and keeps the session moving.
- After skipping sessions, the next plan visibly rebalances toward what was
  missed — without him configuring anything.
- Monthly InBody upload takes seconds and produces a readable trend.
- He keeps using it for 3+ months — the real test.
