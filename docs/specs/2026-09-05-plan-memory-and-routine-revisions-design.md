# Plan-Generation Memory Wiring + Ask Coach Routine Revisions — Design

## 1. Goal

Close two remaining items from the roadmap in one pass, because they're the same
underlying mechanism: (a) wire `MemoryRecall` into plan generation — the
design doc's own §5.2(2) gap ("today nothing does this; every call site either
has no memory or would need the raw list") — and (b) Ask Coach Part 3
(`propose_routine_revision`, permanent routine changes). A "permanent"
revision only means anything once the athlete's next plan actually reads
memory and honors it — building the tool without the wiring would produce a
proposal that's immediately forgotten at the next `generateAndStore`.

## 2. Rulings (decided without a user round-trip, per standing instruction to complete the roadmap autonomously)

- **No dedicated Plan-review screen.** The original design spec named one
  ("`propose_routine_revision`... should get a more deliberate confirmation...
  full review in Plan, not a one-tap accept") because it assumed a revision
  directly edits session structure. Since this app regenerates its plan from
  scratch weekly (`generateAndStore` calls `RulePlanBuilder`/the AI path fresh
  each time — nothing here persists a hand-edited plan forward), a
  "permanent" revision can only work by feeding a durable *preference* into
  the next generation, not by editing a specific week's `PlannedSession`
  array. `CoachMemory`'s existing consolidation pipeline (low starting
  confidence, per-kind cap, confidence×recency decay) already *is* a
  deliberate-confirmation mechanism in spirit — a stated preference doesn't
  dominate the next plan outright, it's one weighted input alongside the
  volume-landmark math. Building a second, heavier review-and-commit UI for
  the same underlying concept (an accepted athlete preference) is
  disproportionate scope. This ruling downgrades §3's "full review" language;
  the spec's own intent (revisions shouldn't be a careless one-tap action)
  is preserved by the fact that `propose_routine_revision` is a stated
  preference persisted via the same trustworthy pipeline everything else in
  this app's memory layer already goes through, not a one-tap session mutation.
- **`propose_routine_revision` writes directly**, not through a
  `PendingCoachSuggestion` card. It's a `CoachMemory` write (kind:
  `preference` or `goal`), applying `MemoryConsolidation.reconcile` exactly
  like the memory-keeper call does — deterministic, capped, low-confidence
  start. The chat reply confirms in plain language ("Noted — I'll favor more
  shoulder volume in future plans").
- **Memory digest reaches both the AI path and doesn't break the rule-engine
  path.** `RulePlanBuilder` is deterministic math with no text-prompt
  concept — memory can't literally influence it without real engineering
  (e.g., bumping a volume landmark based on a memory tag), which is out of
  scope for this pass. This pass only wires memory into the **AI plan
  generation path** (`PlanCoordinator`/`PlanPromptBuilder`), matching the
  design doc's own item (it names "plan generation," which is the AI path –
  the rule engine is a separate, pre-existing deterministic fallback this
  pass doesn't touch).

## 3. Plan-generation memory wiring

`PlanPromptBuilder.user(context:priorIssues:memoryDigest:)` gains a new
parameter; `PlanCoordinator.makePlan` gains a `memoryDigest: String`
parameter threaded straight through to both the initial and retry prompt
builds. `generateAndStore` (in `AI/PlanGeneration.swift`) builds the digest
before calling `PlanCoordinator`: fetch `CoachMemoryModel`, map to domain,
`MemoryRecall.select(from:context: RecallContext(), now: .now)` (empty
context — plan generation isn't scoped to specific exercises the way finalize
is), pass `recalled.digest` (the existing ID-less, confidence-filtered
digest is correct here — plan generation never needs to reinforce/contradict
a memory, only read it, exactly like `SessionFinalizeCoordinator`'s existing
use of `recalled.digest`).

## 4. `propose_routine_revision` tool

New `CoachTool` for `AskCoachCoordinator`: `propose_routine_revision(statement:
String, action: String?)` — the model states the durable preference in its
own words (e.g. "Wants more shoulder volume on push days") plus an optional
concrete action hint. The tool wraps this as a `MemoryCandidate(kind:
.preference, statement:, action:, tags: MemoryTags(), relation: .new)` and
calls `MemoryConsolidation.reconcile(existing:candidates:now:)` directly
(existing memories fetched fresh from `ModelContext`, same "coordinator that
writes must read live" lesson the memory-keeper plan's own final review
learned), persisting via `coachMemoryModel(from:)`.

`AskCoachPromptBuilder.system()` gains a sentence: for a *permanent* program
change (not a single session), use `propose_routine_revision` instead of the
session-scoped propose tools; it becomes a standing preference that
influences future plan generation, not an immediate change.

## 5. Non-goals

- Editing the rule-engine's deterministic volume math based on memory.
- A dedicated review UI for routine revisions (ruled out above).
- Retroactively applying a routine revision to the current week's already-
  generated plan (it only affects the *next* `generateAndStore` call).
