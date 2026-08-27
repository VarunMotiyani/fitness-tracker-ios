# 02 — Product Design

_Date: 2026-08-27_

How the app behaves. Technical implementation is in
[03-technical-architecture.md](03-technical-architecture.md).

---

## 1. Core principle: the plan is a rolling target, not a calendar

The engine produces a **week of sessions** (e.g. 4), each with muscle-group
volume goals. It never assigns weekdays. The user trains when they train. Every
time the app opens, the plan is **recomputed from actual history**. Nothing is
ever "missed" — it rebalances.

---

## 2. Onboarding

One-time setup. Rarely asks again. All fields editable later.

| Field | Purpose |
|-------|---------|
| **Goal** (lose fat / build muscle / get stronger / general fitness) | One primary, weighted. Drives rep ranges, volume, exercise selection bias. |
| **Experience** (true beginner / ~6 months / 1yr+) | Starting volume, progression speed, exercise complexity. |
| **Body stats** (height, weight, age, sex) | Load estimates, volume landmarks. Weight updates over time. |
| **Schedule capacity** (sessions/week + length: 30/45/60/90 min) | A **ceiling**, not a commitment. Rolling plan works off actual behaviour. |
| **Equipment** (checklist: barbell, dumbbells to X kg, cable stack, leg press, hack squat, …) | The only pool the engine and swaps draw from. |
| **Limitations** (injury/pain flags: lower back, left shoulder, knees…; hard "won't do" list) | Hard exclusions. |

Changing equipment or limitations triggers a re-plan.

---

## 3. The adaptation model

Three points where the plan adapts:

### 3.1 Re-plan on demand (every app open)
Compares completed volume this week against per-muscle-group goals. Trained chest
and back, skipped legs twice → next session served is leg-focused. At week
rollover, undertrained groups get priority in the new week.

### 3.2 Pre-session check (tap "Start workout")
Two questions: **how's your energy?** and **how much time do you have?**
- Low energy / short time → trim to essential compounds, cut a set, shift to less
  taxing machine variants.
- Strong + time → add a set or nudge target load.

### 3.3 Post-session feedback
Per exercise (or overall): **easy / right / brutal**, plus optional note
("left shoulder pinched on incline press"). Feeds:
- progression math for next time (easy → add load; brutal → hold/back off),
- a running **niggle list** the engine sees when planning.

### 3.4 Guardrails (rule layer, always on)
- Per-session load-increase cap.
- Weekly volume per muscle group kept inside experience-appropriate **min/max
  landmarks**.
- Flagged injuries **force-exclude** matching exercises.
- Enforced rest gap between heavy sessions for the same muscle group.

---

## 4. Training knowledge

The user never picks or names a split. **No program picker.**

- The **AI model** brings the canon: PPL, Arnold, Upper/Lower, PHUL/PHAT,
  full-body, bro split, 5/3/1, GZCLP, nSuns, 5×5, RPE programming, periodization,
  volume-landmark thinking.
- The **app pins down** what shouldn't rely on model memory:
  - well-known split structures encoded as real **templates** (full body,
    upper/lower, PPL, Arnold) with set/rep schemes,
  - the **catalog** constrains which exercises can be prescribed,
  - if named-program fidelity is ever wanted, that program's progression is
    hard-coded, not regenerated.
- The engine may surface a one-line **"why this plan"**; the user is never asked
  to manage it.

---

## 5. InBody scan analysis

1. **Upload** a photo of the monthly InBody result sheet.
2. Vision model extracts: weight, **PBF %**, **SMM**, BMR, total body water,
   protein mass, mineral, visceral fat level, InBody score, **segmental lean
   analysis** (L/R arm, trunk, L/R leg), scan date.
3. **Review screen** — user confirms the numbers before save (vision can misread
   a digit; this data drives everything).
4. Stored as a **time series** → trend view: PBF, SMM, weight over months. The
   real "is it working?" signal — SMM up while PBF drops = plan + effort paying
   off.
5. **Feeds the engine:**
   - SMM flat despite consistent hard training → dial in recovery/volume, flag
     nutrition as the likely limiter.
   - Clear L/R segmental imbalance → bias toward unilateral work.
   - Deep segmental-imbalance programming is a later refinement; v1 does
     extract → confirm → trend → a couple of signals into the planner.

---

## 6. The in-gym session flow

### Start
Tap **Start workout** → energy + time questions → engine finalizes today's
session from the rolling plan → exercise list shown.

### During — one exercise at a time
- Name, target sets × reps, target weight (last logged weight for that lift +
  progression rule).
- Instruction image(s) + a few form cues from the catalog.
- Log each set: reps + weight, target pre-filled (usually one tap). Rest timer
  auto-starts after a logged set.
- Per-exercise feedback on finishing it: easy / right / brutal + optional note.

### Machine occupied — the swap
One tap on **Swap** → engine offers 2–3 alternatives that:
- hit the same **primary muscle**,
- need equipment the user has (and is presumably free),
- match the intended **rep range**.

Example: hack squat taken → leg press, goblet squat, Bulgarian split squat. Pick
one; target weight carries over adjusted for the movement. The swap is remembered
**for the session only** — it doesn't permanently change the plan (but repeated
manual swaps do shift the engine's default, see §7).

### Finishing
Optional overall note → summary: what was done, volume vs. target, any PRs.
Writes to history, updates the rolling weekly picture.

### Abandoning
End a session partway anytime. Logged work counts. The remainder flows back into
the week's remaining volume.

---

## 7. The feedback loop — what propagates, and when

| Horizon | What updates |
|---------|--------------|
| **Next session** | Logged weights become baselines. "Easy" → load up (within cap). "Brutal" / missed reps → hold or back off. Niggle note → deprioritize/swap that exercise + add to limitations list. Repeated manual swaps → engine changes its default exercise. |
| **Rest of this week** | Completed vs. goal volume per muscle group decides the next session's emphasis. |
| **Next week (rollover)** | Undertrained groups prioritized. Broad progress → advance the whole plan (load, sometimes volume, occasionally structure). Many "brutal" + stalled lifts → lighter, deload-style week. |
| **Monthly (InBody)** | Scan trend is the long-range check. SMM climbing + PBF dropping → stay the course. SMM stalled despite consistency → recovery/volume adjustment + nutrition flag. |

The plan is never static — recomputed from actual history on every app open.

---

## 8. Notifications

Local only (no server). All toggleable. Not guilt-heavy by default.

- Session reminders at set times (adjustable, snoozable).
- Nudge if no training in X days **and** weekly volume unmet.
- Monthly "time for an InBody scan" reminder.
- Rest-timer alerts during a session.

---

## 9. Scope boundaries (v1)

**In:** onboarding, exercise catalog, AI plan generation, rolling adaptation,
pre-session check, in-gym session view + set logging, machine-occupied swap,
history + progression, InBody photo ingestion + trend, local notifications,
BYO API key, month-to-date cost estimate.

**Not in v1:** food/calorie/macro tracking · Apple Watch app · HealthKit sync ·
iCloud multi-device sync · social/sharing · video content · multi-user · program
picker UI.
