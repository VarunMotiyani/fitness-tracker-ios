# Memory-Keeper Call — Design

## 1. Goal

`FitnessCore/Sources/CoachMemory` is fully built and tested — `CoachMemory`,
`MemoryConsolidation.reconcile`, `MemoryRecall.select`, per-kind cap with
confidence×recency eviction — but nothing produces the `MemoryCandidate`s
`reconcile` consumes. This is the gap called out in
`docs/specs/2026-09-05-ai-coach-layer-v2-design.md` §5.2(1): the memory layer
can consolidate and recall, but nothing writes to it yet. This plan builds the
one missing piece: an LLM call that reads a finished session and produces
memory + measurement candidates, wires it into the existing deterministic
consolidation pipeline, and persists the result.

This is Part 2 of the AI Coach Layer v2 (Part 1 was the finalize vertical
slice, `docs/plans/2026-09-05-ai-coach-orchestrator-core.md`). It does not
build Ask Coach, coverage-gap suggestions, proactive notifications, or the
nightly batch variant of this same call — those stay follow-on work per
§5.2(1)'s "run in two places, not one" note (this plan builds the session-end
place only) and per the design doc's own scope note.

## 2. Trigger

Hooked into `SessionRunner.finish(partialReason:overallNote:)`, immediately
after it persists the session/PRs/outcome, as a detached, non-blocking
`Task`. The transition to `.summary` happens immediately regardless of
whether — or how fast — the call completes; the memory-keeper result lands
whenever it lands, same "never block on network" rule the finalize call
already follows.

`overallNote` — the free-text field already collected on the summary screen
via `finish`'s `overallNote` parameter — is this slice's "tell the coach
something" channel. No chat UI exists yet; this is the one place today where
you can hand the model unstructured text, so it's exactly what the
memory-keeper call reads.

## 3. Inputs

Mirrors the finalize call's shape (design spec §8's orchestration pattern:
one well-orchestrated call per touchpoint, full context, model does its own
reasoning):

- The just-finished `CompletedSessionSnapshot` (`session.toSnapshot()` —
  already available on `CompletedSessionModel`). Carries `overallNote`,
  per-entry feel ratings, sets/reps/load actually logged, `outcome`,
  `partialReason`.
- Today's `DailyCheckinSnapshot` if one exists (sleep quality, soreness,
  note) — fetched by date from `DailyCheckinModel`.
- The current live `[CoachMemory]` — non-retired, non-cap-evicted — so the
  model can decide `.new` / `.reinforces(id)` / `.contradicts(id)` per
  candidate, exactly as `MemoryConsolidation.reconcile` expects.
- `QueryTrainingDataTool`, registered exactly as in `SessionFinalizeCoordinator`,
  so the model can pull further history via `PulseQuery` if the day's data
  alone doesn't explain something (e.g. "is this soreness a new pattern or a
  one-off?") — no pre-loaded history window; the tool loop lets the model
  decide when it needs more.

## 4. Output schema

New `MemoryKeeperDTO`, decoded via the same provider-agnostic tool loop
(`ToolLoopRunner`, `ToolLoopTurn`) the finalize call uses:

```swift
struct MemoryKeeperDTO: Codable, Sendable {
    let memoryCandidates: [MemoryCandidateDTO]
    let measurementCandidates: [MeasurementCandidateDTO]
}

struct MemoryCandidateDTO: Codable, Sendable {
    let kind: String          // MemoryKind.rawValue
    let statement: String
    let action: String?
    let exerciseID: String?
    let muscle: String?       // MuscleGroup.rawValue
    let equipment: String?    // Equipment.rawValue
    let freeTags: [String]
    let relation: String      // "new" | "reinforces" | "contradicts"
    let relatedMemoryID: String?  // UUID string, required when relation != "new"
}

struct MeasurementCandidateDTO: Codable, Sendable {
    let kind: String   // e.g. "bodyFatPercent", "bodyweightKg" — same `kind`
                        // vocabulary ObservationModel already uses
    let value: Double
    let unit: String
}
```

Both arrays may be empty — most sessions produce no new facts, and that's the
expected common case, not a failure.

## 5. Memory path

`MemoryCandidateDTO` → `MemoryCandidate` (decode `relation`, resolve
`relatedMemoryID` to a `UUID`, drop the candidate if `relation != "new"` but
the id fails to parse — treat as `.new` per `reconcile`'s own "unknown id"
handling) → `MemoryConsolidation.reconcile(existing:candidates:now:)`.

No additional guardrail — `reconcile` is already the guardrail: fixed
starting confidence (0.3) for new/contradicting facts, per-kind cap (12),
confidence×recency eviction. This is the "model never writes" principle in
its purest form here: the LLM's output never touches SwiftData directly, it
only proposes; `reconcile` is deterministic and already shipped and tested.

Persistence: for each `ConsolidationResult`,
- `writes` → `coachMemoryModel(from:)`, `context.insert(...)`
- `updated` → find the existing `CoachMemoryModel` by `id`, mutate its stored
  properties from the updated `CoachMemory` in place
- `retired` → find the existing `CoachMemoryModel` by `id`, set
  `supersededBy`/`retiredByCap` from the retired `CoachMemory`

## 6. Measurement path

`MeasurementCandidateDTO` → `MeasurementGuardrail.check(kind:value:)`, a new,
small, pure function rejecting implausible values per known kind (e.g.
`bodyFatPercent`: 3–60, `bodyweightKg`: 30–300; an unrecognized `kind` string
is rejected outright — never write a kind the app doesn't already chart).
Values that pass become a new `ObservationModel` row with `confirmed = false`.

`ObservationModel.confirmed: Bool` is a new stored property, defaulting to
`true` in `init` — every existing and future manually-entered observation
stays confirmed by construction; only this new AI-derived write path ever
sets it `false`.

**Unconfirmed observations are excluded** from:
- `HistoryExportManager.exportFullJSONData`'s `observations` array (so an
  unconfirmed, possibly-wrong number can't feed back into the next AI call's
  own `QueryTrainingDataTool` reasoning), and
- the Stats screen's charts/aggregates,

until confirmed. This is enforced by filtering `confirmed == true` at the two
read sites, not by hiding the row from SwiftData entirely — the pending card
(§7) still needs to read it.

## 7. Review surface

A card on the Home tab, visible whenever at least one `ObservationModel` has
`confirmed == false`: "Coach noticed: `{value} {unit}` ({kind}) — confirm?"
with inline **Accept** (`confirmed = true`) and **Dismiss** (delete the row).
Multiple pending observations stack as multiple cards (uncommon in practice —
one session produces at most a handful of measurement candidates, usually
zero).

## 8. Failure handling

No provider configured → the call never starts. Provider throws, tool loop
exceeds its cap, or the final decode fails → the whole call is abandoned
silently: nothing written, no error surfaced, no retry. Unlike finalize
(which must produce *some* session either way, hence its rule-engine
fallback), memory-keeper has no obligation to produce anything — "no new
facts learned this session" is always a valid, silent outcome.

## 9. Billing

One `AICallRecord` per underlying provider call actually made
(`callType: "memoryKeeper"`), same call-granular pattern as finalize
(`docs/plans/2026-09-05-ai-coach-orchestrator-core.md` Task 7, and the
`ToolLoopResult<Final>` / `CallOutcome` plumbing added to fix finalize's own
gap). `usedFallback` is always `false` for this call type — there is no
fallback path, only "ran" or "silently skipped," and a skipped call writes no
record at all (nothing to bill).

## 10. Non-goals for this slice

- **Nightly batch variant** — deferred until the notifications/scheduling
  subsystem exists (design spec §7 items #6-#8).
- **Ask Coach as a second trigger** — deferred to the Ask Coach plan; this
  slice only wires the session-end trigger. The memory-keeper logic itself
  (prompt builder, DTO, consolidation, persistence) is written as a
  standalone, reusable unit precisely so Ask Coach's plan can call the same
  pipeline with different input assembly, not rebuild it.
- **Closing the `MemoryOutcome` loop** (design spec §5.2(3)) — a suggestion's
  `outcomeScore` feedback is separate work, needs the coverage-gap suggestion
  UI to exist first (a memory can't get outcome feedback from a suggestion
  that doesn't exist yet).
- **Wiring `MemoryRecall` into plan generation** (design spec §5.2(2),
  partial) — only finalize reads memory today; plan generation is a separate,
  small follow-up once this call is producing real memories to recall.

## Self-review

- **Placeholder scan**: no TBDs; every field in `MemoryKeeperDTO` maps to a
  concrete existing type or a new, fully-specified guardrail.
- **Consistency**: `MeasurementCandidateDTO.kind` deliberately reuses
  `ObservationModel.kind`'s existing string vocabulary rather than inventing
  a parallel enum — one source of truth for "what kinds of measurements
  exist," checked by `MeasurementGuardrail` against that same vocabulary.
- **Scope**: this is the session-end trigger and the persistence pipeline
  only. Ask Coach, the nightly batch, `MemoryOutcome`, and `MemoryRecall` in
  plan generation are explicitly out — each is its own future plan, per §10.
