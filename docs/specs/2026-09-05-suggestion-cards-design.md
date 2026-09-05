# Suggestion Cards — Ask Coach Part 2 + Coverage-Gap UI — Design

## 1. Goal

Build the generic "suggestion card" component design spec §3 described from the start
("one reusable component — rationale line + Accept/Skip — used for coverage gaps,
substitutions, recovery-based reschedules, deload nudges, and anything Ask Coach
proposes") and wire two producers into it in one pass: Ask Coach proposing a
session-scoped change via chat, and a deterministic coverage-gap detector that runs
after plan generation. Building both together avoids building the card twice.

This is Ask Coach Part 2 (Part 1 = chat, shipped). Part 3 (permanent routine
revisions via a Plan-review screen) stays separate — this part only ever mutates
one not-yet-started `PlannedSession` inside the current week's `StoredPlan`, never
a whole routine.

## 2. Rulings (decided without a user round-trip, per explicit instruction to complete this end-to-end)

- **Scope of what can be proposed**: exercise swap (`propose_exercise_swap`) and a
  set/rep/load adjustment (`propose_set_change`) on one `PlannedItem` within one
  `PlannedSession` that hasn't started yet. Not a permanent routine change (Part 3),
  not a change to a session already in progress (that session's live
  `CompletedSessionModel` has already diverged from the stored plan — its own
  in-session swap/adjust UI is the right tool for that, not a suggestion card).
- **Suggestion storage**: one new model, `PendingCoachSuggestion`, flat fields (no
  JSON blob) since there are only two proposal kinds.
- **Rendering location**: one place — a card list on the Home tab, same pattern as
  the memory-keeper plan's `PendingObservationCard`. Not duplicated into Plan or
  the session-start screen for this pass.
- **MemoryOutcome loop**: not wired in this pass. `PendingCoachSuggestion` has no
  `sourceMemoryID` link. This remains open, documented, future work — the design
  doc's own §5.2(3) already named the dependency ("needs the coverage-gap
  suggestion UI to exist first") and this pass builds that UI, but doesn't yet
  spend the extra design effort connecting accept/reject back to a specific
  memory's `outcomeScore`.
- **Coverage-gap detector**: deterministic (no LLM call) — reuses the existing
  `MuscleBalanceModel.rankOf` (already computed for `AskCoachCoordinator`'s
  `get_muscle_balance` tool) to find `missed` muscles, and proposes adding one set
  of a suitable exercise for the least-recently-worked missed muscle to the next
  upcoming session that already targets a muscle group covering it. Runs once,
  right after `generateAndStore` produces a new plan (§7 trigger #1 in the AI
  Coach Layer v2 design doc — "Onboarding completes" — extended to also run after
  any regenerate).

## 3. Data model

**`PendingCoachSuggestion`** (new `@Model`):
- `id: UUID`, `plannedSessionID: UUID`, `kind: String` (`"exerciseSwap"` |
  `"setChange"`), `exerciseID: String` (the item being changed),
  `replacementExerciseID: String?` (swap only), `targetSets: Int?`,
  `targetRepsMin: Int?`, `targetRepsMax: Int?`, `targetLoadKg: Double?` (setChange
  only — any subset may be non-nil, meaning "change only this field"),
  `rationale: String`, `source: String` (`"askCoach"` | `"coverageGap"`),
  `createdAt: Date`, `resolvedAt: Date?`, `accepted: Bool?` (nil = pending).

## 4. Ask Coach's two new propose tools

Both are `CoachTool`s added to `AskCoachCoordinator.buildTools()`. Unlike the three
existing read tools, these don't return data for the model to reason further with —
they write a `PendingCoachSuggestion` row directly (the tool's `run` has
`ModelContext` access, same as any other tool) and return a short confirmation
string. This is still "the model never writes directly" in spirit: the tool's
`run` is deterministic Swift code the model merely triggers with structured
arguments, identical in kind to how `MemoryConsolidation.reconcile`/
`MeasurementGuardrail` are deterministic gates the model's *output* passes through
— here the gate is just "insert a proposal row," not "call an LLM-authored value
plausible."

`propose_exercise_swap(plannedSessionID: String, exerciseID: String,
replacementExerciseID: String, rationale: String)` — validates
`plannedSessionID` resolves to a real, not-yet-completed session in the current
`StoredPlan` and `replacementExerciseID` exists in the catalog before writing;
returns an error string (not a crash) on either failure, exactly like every other
tool's `decodeArgs`-fails-silently contract.

`propose_set_change(plannedSessionID: String, exerciseID: String, targetSets:
Int?, targetRepsMin: Int?, targetRepsMax: Int?, targetLoadKg: Double?, rationale:
String)` — same validation, plus a plausibility bound reusing `FinalizeGuardrail`
semantics loosely (sets 1-10, reps 1-30, load 0-500kg) so a hallucinated absurd
number doesn't reach the card.

A new read tool, `get_upcoming_sessions()`, gives the model the current week's
not-yet-started sessions (id, order, focus muscles, exercise list) so it can
resolve "Tuesday's session" to a real `plannedSessionID` before calling either
propose tool — without this, the model has no way to know what IDs exist.

`AskCoachPromptBuilder.system()` gains one paragraph: propose tools exist now: use
them when the athlete asks for a concrete change to an upcoming (not in-progress)
session; if they're asking about the session they're currently in, tell them to
use the swap/adjust controls in the session screen instead, since a suggestion
card can't reach a session already underway.

## 5. Accept / Skip mutation

A card's Accept button calls a new `SuggestionApplier.apply(_:in:catalog:)`:
decode the `StoredPlan` matching the suggestion's `plannedSessionID`'s week,
rebuild the target `PlannedSession`'s `items` array with the mutation applied (new
`PlannedItem` value replacing the old one at the matching `exerciseID`, same
copy-and-rebuild pattern `RuleEngineFinalizer`/`SessionFinalizeCoordinator`
already use), re-encode, write back to `StoredPlan.planJSON`, mark the suggestion
`resolvedAt = .now, accepted = true`. Skip just marks `resolvedAt = .now, accepted
= false` — no plan mutation.

## 6. Coverage-gap detector

`CoverageGapDetector.detect(context:catalog:)`, called once from `generateAndStore`
right after a plan is stored: builds the same `[EffectiveSetItem]` shape
`AskCoachCoordinator.buildTools()` already builds, calls
`MuscleBalanceModel.rankOf(load:)`, and for each `missed` muscle picks the
first upcoming `PlannedSession` whose `focusMuscles` already includes a muscle in
the same body region (reusing `MuscleBalanceModel`'s canonical-slug grouping) and
proposes adding one set of a catalog exercise targeting the missed muscle,
inserted as a NEW `PlannedItem` (not a swap) — kind `"exerciseSwap"` doesn't fit an
addition, so `PendingCoachSuggestion` needs a third kind, `"addExercise"`, with
`replacementExerciseID` reused as "the exercise to add." One suggestion per missed
muscle per plan generation, capped, skips a muscle that already has an unresolved
pending suggestion for it (no duplicate spam every regenerate).

## 7. Home UI

`SuggestionCard.swift` (new, reusable): rationale text + Accept/Skip, same visual
language as `PendingObservationCard`. `HomeView` queries
`PendingCoachSuggestion` where `resolvedAt == nil` (Swift-side filter, not
`#Predicate`, per this project's own established rule) and renders one card per
row, right below the pending-observations section.

## 8. Non-goals

- MemoryOutcome wiring (documented above, explicit future work).
- Permanent routine revisions (Part 3).
- Suggestions surfaced anywhere but Home.
- A "why was this suggested" expandable detail — the one-line rationale is it.
