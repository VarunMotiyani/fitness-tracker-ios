# AI Coach Layer v2 — Design

_Date: 2026-09-05. Status: draft for review._

**Parent:** `docs/specs/2026-08-29-phase-2-session-runner-design.md` §4 (agent
layer), §5 (the `finalize` call). Supersedes the capability list in that spec's
§4 — everything below is written against the app as it actually stands tonight
(equipment profiles, two exercise-media sources, the rebuilt session runner,
`MuscleBalanceModel`, the session-list substitute flow), not the Phase 2
baseline it was originally written against.

**Prior art already built, being resumed rather than redone:**
- `docs/superpowers/plans/2026-08-30-phase-2c-i-ai-session-finalize.md` (on the
  parked branch `phase-2c-i-ai-session-finalize`, Task 1 committed at
  `558b27d`) — the `SessionFinalizeCoordinator` / `FinalizeGuardrail` /
  `RuleEngineFinalizer`-fallback plumbing. Resumed as-is as Task Group A below.
- `AI/PlanCoordinator.swift`, `PlanGeneration.swift`, `PlanDTO.swift`,
  `PlanPromptBuilder.swift` (Phase 1c) — whole-plan generation already works
  (`callType: "planGeneration"`). Extended, not rebuilt, in Task Group B.
- `FitnessCore/Sources/CoachMemory/*` — the memory *substrate* (model,
  consolidation, recall, decay, per-kind cap) is fully built. What's missing is
  what feeds it and what reads from it — Task Group E.

---

## 1. Goal

Everything the AI layer produces — a finalized session, a plan revision, a
coverage-gap suggestion, an answer to a free-text question — is real data the
app already knows how to render, checked by the same deterministic guardrails
either way, with a memory layer that gets *more* useful over time without
growing the context sent on every call, and an escape hatch to read exact
historical facts that memory doesn't (and shouldn't) keep as a standing belief.

**Done when:** every capability in §2 lands as one of the two shapes in §3 (a
typed result the existing UI renders, or a suggestion card you accept/skip);
the memory layer is fed by a real memory-keeper call and every AI call site
reads from it via `MemoryRecall`, not from nothing or from the raw list; the
JSON query tool answers an exact historical question the digest doesn't cover.

---

## 2. Capability list

### 2.1 Already shipped, unchanged
- **Plan generation** (Phase 1c) — cold-start weekly split from goal/experience/days.

### 2.2 Resumed from the parked plan (Task Group A)
- **Session finalize** — reorder/trim/progress today's session. LLM call →
  `FinalizeDTO` → `FinalizeGuardrail.check` → retry once with violations fed
  back → `RuleEngineFinalizer` fallback. Cost-logged (`AICallRecord`,
  `callType: "finalize"`). Fully offline-safe (no provider configured behaves
  exactly like today).

### 2.3 New capabilities (Task Group B–D)
- **Plan generation, made equipment- and history-aware.** Reads the active
  `EquipmentProfile` (never proposes a smith-machine exercise for a
  "Travel/Hotel" profile) and, for a returning user, `MuscleBalanceModel`
  history (a revision isn't cold-started every time).
- **Coverage-gap suggestions.** Scope decision (confirmed): checked against
  exactly what a routine's own `focusMuscles` declares — not an inferred
  anatomical expansion the routine never asked for. Per declared muscle,
  `MuscleBalanceModel` volume over a rolling window (last 3 sessions of that
  routine) below a floor → a `MuscleCoverageGap`, surfaced as a suggestion card
  on `SessionStartView` with a candidate exercise (same matching approach as
  `ExerciseSwapSheet`). Accept appends it to the session before Start; Skip
  dismisses for this session only.
- **Substitution reasoning.** `ExerciseSwapSheet`/`runner.swapExercise` are
  user-initiated mechanics already built. This is the layer that *notices* a
  swap is warranted — equipment profile no longer covers today's exercise, an
  exercise note mentions pain/discomfort, or a pattern of repeated substitution
  the memory layer has recorded — and offers it as the same suggestion-card
  shape, never forces it.
- **Recovery-aware pacing.** `RecoveryModel` fatigue is computed and currently
  unused by anything. Finalize should be able to propose a schedule-level
  swap ("chest is at 40% recovery — swap today for the pull day instead?"),
  via `propose_schedule_change` (§4).
- **Personalized rationale text.** The progression banners are templated
  strings (`WhyTemplate`) today. AI generates the *explanation* in natural
  language; the load/set/rep **number** stays rule-engine-decided and
  guardrail-checked either way — AI explains, the rule decides, never the
  reverse.
- **Ask Coach.** Free-text entry point. Maps to the *same* small set of typed
  actions everything else uses (§4) — never a freeform response untraceable to
  a real action. Ambiguous input → `ask_clarifying_question`, not a guess.

### 2.4 Explicit non-goals
- No web/internet access for the AI layer, ever — stays local-first and
  self-contained, same reasoning as the rest of the app.
- No direct UI mutation from the AI (see §3) — every capability above lands as
  one of two fixed shapes.

---

## 3. How AI output reaches the screen

**The AI never generates UI. It generates data shaped exactly like what
deterministic code already produces**, and the screens built tonight render it
without knowing or caring which source produced it.

Two shapes cover every capability in §2:

1. **A typed result the existing UI already renders** — finalize's output is a
   `PlannedSession`/`FinalizedSession`, the exact type `RuleEngineFinalizer`
   already produces. `SessionFocusView`, `SessionListView`, `SessionStartView`
   render it unmodified. An AI-picked workout is pixel-identical to a
   rule-engine one, except the rationale reads more naturally and (if the
   guardrail rejected it) a "backup coach" badge appears.
2. **A suggestion card** — one reusable component (rationale line + Accept /
   Skip), used for coverage gaps, substitutions, recovery-based reschedules,
   deload nudges, and anything Ask Coach proposes. Accept calls the same
   mutation functions already built (`runner.swapExercise`, appending a
   `PlannedItem` before Start). Every accept/reject writes an outcome back to
   `CoachMemory` (§5).

The "backup coach" badge (already planned for finalize in the 2c-i plan)
appears on *every* AI-attributed surface that fell back to deterministic
behavior — plan generation, substitutions, Ask Coach — not just finalize, so
you always know which one you got.

`propose_routine_revision` (a *permanent* change to a routine, not just
today's session) is the one exception worth flagging: it affects every future
session, not one, so it should get a more deliberate confirmation than the
lightweight accept/skip card — full review in Plan, not a one-tap accept.

---

## 4. Tools

Grouped by risk, since that determines what guardrail (if any) each needs.

### 4.1 Read tools — safe, no state change
- `get_recovery_status(muscle?)` — live `RecoveryModel` value, not raw history
  the model would have to re-derive (and could get wrong).
- `get_muscle_balance(windowDays)` — live `MuscleBalanceModel` value.
- `get_equipment_profile()` — what's actually available right now.
- `search_exercise_catalog(muscle, equipment, mechanic)` — substitute
  candidates. Kept separate from the JSON query tool (§4.4): the exercise
  catalog is static bundled data, not the growing "everyday data" the query
  tool is for — different lifecycle.
- `get_pr_history(exerciseID)` — typed, common enough to deserve its own path.
- `get_upcoming_plan(days)` — what's scheduled this week, so a reschedule
  suggestion can reason about what it'd be swapping with.

### 4.2 Deterministic math tools — route every exact number through these
LLMs are unreliable at precise arithmetic. Anywhere the AI needs a number, it
calls a tool that runs the existing deterministic code — it never computes the
number itself:
- `estimate_one_rep_max(loadKg, reps)` → wraps `Estimated1RM`.
- `plate_math(targetLoadKg, barType)` → wraps `PlateMath`.
- `convert_units(value, from, to)`.
- `check_progression(currentLoad, history)` → wraps `ProgressionRule` directly,
  so a proposal can be self-checked against the same rule the guardrail
  checks anyway, catching a bad proposal before a retry round-trip.

### 4.3 Propose tools — guardrailed, always land as a suggestion (§3)
- `propose_substitution(entryIndex, newExerciseID, reason)`
- `propose_schedule_change(date, newRoutineID, reason)`
- `propose_routine_revision(routineID, changes)` — gets the fuller-review
  treatment noted in §3, not the lightweight card.

### 4.4 The JSON query tool — read-only, general-purpose escape hatch
Memory (§5) is deliberately small and curated — general, reusable facts. Some
questions need an exact, one-off historical lookup that was never important
enough to become a standing memory ("what was my squat 1RM in March"). Rather
than bloat every prompt against that possibility, the AI gets a tool call:

- **One JSON shape, reused**: `HistoryExportManager`'s existing backup-export
  JSON (sessions, sets, bodyweights, PRs, routines — already built for the
  manual "Export backup" Settings feature) is the snapshot the query engine
  reads. No second data format to maintain.
- **The query language**: a small, dependency-free, JMESPath-inspired subset
  in pure Swift over an in-memory parsed JSON tree — dot-paths
  (`sessions[].entries[]`), filters (`[?exerciseID=='0025']`), and a handful
  of aggregation functions (`length`, `sum`, `max_by`, `sort_by`, date
  comparisons). Not a full JMESPath clone — only what fitness queries need.
  At this app's real data scale (single-digit MB after years of daily use,
  per the earlier storage estimate — see conversation record), a plain
  tree-walk interpreter is already fast; no indexing layer needed.
- **How the AI reaches it**: a tool call (`query_training_data(query: string)
  -> JSON`), invoked only when the model decides its existing context isn't
  enough — not injected into every prompt.
- **Why it's safe to give broad read access to**: no mutation verbs exist in
  the language at all. This is the one place the AI gets a genuinely *wider*
  scope than the curated digest, and it's safe specifically because "wider"
  only ever means "can read more," never "can do more."

### 4.5 Communication tools
- `ask_clarifying_question(text)` — explicit "I need more info" response type
  for Ask Coach, instead of a guess dressed up as an answer.
- `schedule_reminder(message, date)` — hooks into the existing local
  notification system. Touches OS permissions, so it needs its own small
  guardrail (a rate limit, so it can't spam reminders).

### 4.6 Explicit non-goal
No web/internet tools — see §2.4.

---

## 5. The memory layer

### 5.1 What's already built (`FitnessCore/Sources/CoachMemory/`)
- **`CoachMemory`** — distilled statements (`kind`: preference / constraint /
  observation / goal / responsePattern), each with a `confidence`, tags
  (exercise/muscle/equipment), and an `outcomeScore`.
- **`MemoryConsolidation.reconcile`** — a candidate fact either creates a new
  memory, **reinforces** an existing similar one (+0.15 confidence, no
  duplicate), or **retires** one it contradicts (superseded, not deleted —
  traceable).
- **Per-kind cap (12 default) with confidence × recency eviction** — the
  self-curating mechanic: when a kind exceeds the cap, the memory that's both
  least confident *and* stalest is evicted first.
- **`MemoryRecall.select`** — filters to memories relevant to the current call
  context (exercise/muscle/equipment), ranks by confidence × recency-decay ×
  outcome-weight, caps to 8, and produces a compact text `digest`. This is the
  "don't send the whole memory every time" mechanism — already built.
- **`recencyWeight`** — exponential decay, half-life 30 days by default.

### 5.2 What's missing
1. **The memory-keeper call itself.** `MemoryConsolidation.reconcile` consumes
   `MemoryCandidate`s; nothing currently produces them. This is an LLM call —
   `source: .agent("memoryKeeper")` is already the literal value
   `freshMemory(from:)` writes — that reads a finished session (sets logged,
   notes, effort ratings, which suggestions got accepted/rejected) and returns
   candidates. Run in two places, not one:
   - **Once per finished session** (training data → candidates).
   - **After a meaningful Ask Coach exchange** (a stated preference, an
     injury mentioned, a goal change) — without this, anything you tell the
     coach in chat is forgotten the moment the conversation closes and never
     reaches plan generation or finalize next time. Same consolidation
     pipeline, different input.
2. **Wiring `MemoryRecall` into every call site.** Finalize, plan generation,
   coverage suggestions, Ask Coach, the daily/weekly proactive calls (§7) —
   each needs to call `MemoryRecall.select` with its own `RecallContext` and
   include the resulting `digest` in its prompt. Today nothing does this;
   every call site either has no memory or would need the raw list.
3. **Closing the `MemoryOutcome` loop.** When a suggestion built from a memory
   is accepted and works out (or is rejected), that should write back to the
   memory's `outcomeScore` — so a bad suggestion pattern actually stops
   recurring instead of only fading passively via recency decay.

---

## 7. Proactive triggers & notifications

Everything through §6 is reactive — it waits for Start or for you to type into
Ask Coach. A personal trainer also reaches out on their own. The trigger list
below is deliberately short: most of what sounds like it needs its own
proactive check is actually the *daily* or *weekly* call below narrating data
that's already computed deterministically, not a new mechanism per capability.

| # | Trigger | Delivery | Call needed? |
|---|---|---|---|
| 1 | Onboarding completes | In-app | `planGeneration` (existing) |
| 2 | You tap Start | In-app | `finalize` |
| 3 | A session finishes | In-app + writes memory | `memoryKeeper` |
| 4 | Guardrail/critic rejects an output | In-app | Automatic retry, same call type |
| 5 | Retry also rejected | In-app | Escalation call to fallback provider (if configured) |
| 6 | **Once daily**, morning | **Local notification** + Home | One short LLM call — "Today: Push Day, focus on triceps" narration; the plan and any coverage gap behind it are already deterministic |
| 7 | **Once weekly** | **Local notification** + a real summary screen, not a toast | One LLM call — sessions done, muscle coverage across the week, streak, PRs, what to prioritize next week. This — not the daily call — is where "which muscle groups need focus" belongs: coverage is a multi-day rolling signal, and a same-day version would flag noise, not a real gap |
| 8 | **Every ~4–6 weeks** | **Local notification** | None — pure scheduled reminder to take an InBody scan, same mechanism as the existing workout-day reminder |
| 9 | Daily check-in logged *and* soreness/sleep crosses a concerning threshold | In-app, and a notification if you haven't opened the app that day | Check-in reaction call |
| 10 | A `responsePattern` memory's confidence/recurrence crosses a threshold (e.g. same session type skipped repeatedly) | In-app | Pattern nudge call |
| 11 | Ask Coach — you type something | In-app | Ask Coach call, plus a memory-keeper pass if it contained a real fact (§5.2) |
| 12 | You manually ask to regenerate a routine | In-app | `planGeneration`/revision |

Steady-state cost at DeepSeek/GLM/Kimi pricing: the floor from #2+#3 (~8/week
at 4 sessions/week) plus #6+#7 (~8/week: one short call/day, one/week) —
roughly 16 calls/week for an active user, before any Ask Coach usage. Trivial
at this pricing tier; not something to economize on by cutting the daily/
weekly narration.

**Delivery mechanism**: #6, #7, #8 route through `schedule_reminder` (§4.5),
the same local-notification system the existing workout-day reminder already
uses in Settings — no new OS-permission surface, just more scheduled content
through it.

---

## 8. Orchestration, for capable-but-affordable models (DeepSeek / GLM / Kimi tier)

These are strong reasoning and agentic-tool-use models at low cost, not weak
models needing to be babysat — the orchestration design should reflect that:

- **One well-orchestrated agentic call per touchpoint, not a manually
  decomposed pipeline of tiny classification calls.** Give the model the full
  context (memory digest, tool access) for finalize or memory-keeper in one
  call and trust its own reasoning to sequence tool calls — that's what these
  models are specifically good at. Manually pre-decomposing into 4–5 narrow
  calls would add latency and round-trips for a model that doesn't need the
  crutch.
- **Ground everything via retrieval regardless.** Not a capability
  workaround — the model has never seen your data unless the memory digest or
  a tool result hands it over. This is a context problem, not a reasoning
  problem, and holds at any model tier.
- **Guardrail + a critic pass stay, for the same reason a good trainer writes
  the program down instead of trusting memory.** The critic call checks the
  highest-stakes output (does the rationale cite a specific retrieved number,
  or is it generic filler) — cheap to run, catches drift even from a strong
  model.
- **Escalate on failure, not by default.** Primary = the configured cheap
  model for every call. Guardrail/critic rejects twice → that one retry
  escalates to a designated pricier fallback `ProviderProfile`, not a
  standing "use the expensive model" policy.
- **Low temperature for decisions, one consistent persona across every call
  type**, reinforced by a `MemoryKind.preference` for communication style.
- **Surface the reasoning trace, don't regenerate it.** DeepSeek-R1 (and
  reasoning-mode variants of the others) already produce a visible
  chain-of-thought as part of normal output — free transparency. Worth an
  optional "Explain more" expansion under the short rationale banner, sourced
  from that trace, not a second call.
- **Cache and skip the call when nothing changed.** Reopening Start without
  touching Energy/Time reuses the last finalize result.

**One correction carried over from §5**: `MemoryKind.constraint` (e.g. "avoid
overhead pressing — shoulder") must be a **hard filter** on every
exercise-selection path (plan generation, finalize, coverage-gap fill-ins,
substitutions) — never merely lowered-likelihood the way a `preference` is.

---

## 9. Open questions for the plan

- Exact low-volume threshold for a coverage gap (§2.3) — a fixed number of
  sets, or relative to the routine's own typical volume for that muscle?
- Where `propose_routine_revision`'s "fuller review" UI actually lives — a new
  sheet in Plan, or a diff view on `RoutineEditView`?
- Rate limit shape for `schedule_reminder` (per day? per week? per muscle
  topic so it can't repeat the same nudge?) — now covers three distinct
  proactive notifications (§7 #6/#7/#8), not just one.
- Exact time-of-day for the daily notification (§7 #6) — fixed, or inferred
  from when you usually open the app / usually train?
- Which provider is the designated escalation fallback (§8), and is it
  user-configured per `ProviderProfile` or a fixed pairing?

These get resolved in the implementation plan, not this design doc — flagging
them here so they're not silently decided by whoever writes Task Group C/D/E.
