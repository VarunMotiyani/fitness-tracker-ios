# Ask Coach — Chat (Part 1: UI + Coordinator) — Design

## 1. Goal

Build the first working slice of "Ask Coach" (design spec §2.1's free-text entry
point, §4's tool set applied to a new touchpoint): a real chat screen where you
can ask the coach questions and tell it things, backed by the same
provider-agnostic tool-loop architecture as `finalize` and the memory-keeper
call. This is Part 1 of Ask Coach — read-only answers and memory-logging only.
Proposing actual changes (exercise swaps, routine revisions) is explicitly
**out of scope** here; it depends on a suggestion-card component and a
`PendingCoachSuggestion` persistence model that don't exist yet (Part 2), and a
Plan-review screen for permanent routine changes (Part 3). This plan produces
a chat that is genuinely useful on its own — you can ask "how's my recovery,"
tell it "shoulder's sore," or ask "what was my squat max in March" — without
waiting on Parts 2/3.

## 2. Data model

**`ChatMessageModel`** (new `@Model`):
- `id: UUID`, `role: String` (`"user"` | `"assistant"`), `text: String`,
  `timestamp: Date`.

**`ChatSummaryModel`** (new `@Model`, at most one row — a singleton):
- `text: String` (the rolling summary, starts empty), `updatedAt: Date`,
  `messagesCoveredThrough: Date` (the timestamp of the newest message folded
  into this summary, so the next summarization pass knows where to resume).

**Rolling summarization.** After a turn is appended, if the count of
`ChatMessageModel` rows exceeds a threshold (30), a background pass:
1. Takes the oldest `(count - 10)` messages (keeping the most recent 10
   verbatim always).
2. Calls the LLM once with the existing `ChatSummaryModel.text` (if any) plus
   those oldest messages, asking for an updated summary that folds the new
   messages into the old summary (not a rewrite from scratch, so key facts
   from a summary-of-a-summary aren't lost).
3. Overwrites `ChatSummaryModel.text`, deletes the folded-in
   `ChatMessageModel` rows.

This mirrors the "recency window + periodic consolidation" pattern
`CoachMemory` already uses for structured facts, applied here to raw
conversational text. It is a separate mechanism from `CoachMemory` — the
summary is for the chat coordinator's own context window (so a long history
doesn't require replaying every message every turn); `CoachMemory` is for
durable, structured facts other call sites (finalize, plan generation) also
need. One new `AICallRecord` per summarization call (`callType:
"chatSummarize"`), same billing pattern as every other call type.

## 3. The chat coordinator

**Trigger:** every time you send a message.

**Inputs:** your new message, the last 10 raw `ChatMessageModel` rows (for
immediate turn-by-turn context), `ChatSummaryModel.text` if non-empty (for
everything older), and a `MemoryRecall.select`-produced digest (same
ID-bearing digest format the memory-keeper call now uses, so a future chat
message could in principle reference an existing memory — not required for
Part 1's read-only scope, but keeping the format consistent costs nothing).

**Tools available:** `get_recovery_status`, `get_muscle_balance`,
`query_training_data` — the existing read-only tools (design spec §4.1),
reused from the finalize/memory-keeper tool set. No propose/mutate tools in
this part.

**Output DTO:** `struct AskCoachDTO: Codable, Sendable { let reply: String }`.
One field, since `LLMProvider.complete` is request/response (this codebase has
no streaming provider capability) — the UI shows a "Coach is thinking…"
indicator, then the full reply appears at once.

**Persona/prompt:** same coach voice as `FinalizePromptBuilder`/
`MemoryKeeperPromptBuilder`, with a hard rule matching design spec §2.1:
ambiguous requests get a clarifying question back, never a guessed answer
dressed up as a real one. Since this part has no propose tools, the system
prompt is explicit that this coordinator only answers and remembers — it does
not (and structurally cannot) change your program.

**Failure handling:** no provider configured → the chat screen shows a
"Set up an AI provider in Settings to talk to your coach" empty state instead
of an input box. Provider throws / tool loop exceeds its cap / decode fails →
the message you sent stays in the transcript, and the assistant's turn shows
a plain inline error state ("Coach couldn't respond — try again") — unlike
finalize/memory-keeper, a chat message can't silently vanish, since you're
looking at it in real time and would notice a phantom non-response. Still
bills only calls that actually ran (`ToolLoopResult.calls`/
`ToolLoopError.exceededMaxIterations(calls:)`, same pattern as finalize and
memory-keeper).

**Billing:** one `AICallRecord` per call actually made, `callType:
"askCoach"`.

## 4. Memory integration

After each full turn (your message + the assistant's reply) completes
successfully, a background, non-blocking pass reuses the existing
memory-keeper machinery: the same `MemoryCandidateDTO`/
`MeasurementCandidateDTO` → `MemoryConsolidation.reconcile` /
`MeasurementGuardrail` → persistence pipeline `MemoryKeeperCoordinator`
already implements, just with a different prompt (a two-message exchange
instead of a `CompletedSessionSnapshot`) and a different entry point.

To share the pipeline without duplicating it,
`MemoryKeeperCoordinator`'s `run(session:)` splits into: (a) a
session-specific prompt-building step (unchanged), and (b) a shared internal
`runToolLoopAndApply(system:user:)` that does the tool loop, billing,
consolidation, and measurement-guardrail application — used by both
`run(session:)` and a new `run(chatExchange:)` entry point this plan adds.
Same silent-no-op contract as the session-end call: most exchanges produce
empty candidate arrays, and that's expected, not a failure.

## 5. UI

**Entry points:**
- A new sixth tab, "Coach" (chat-bubble icon), added to `AppTab`/
  `CustomTabBar` after Exercises.
- A chat-bubble icon in the toolbar of `HomeView`, the active session screens
  (`SessionFocusView`/`SessionListView`), and `PlanView`, each opening the
  same chat as a sheet — so you can reach the coach mid-workout or mid-plan-
  review without losing your place, not only from its own tab.

**Screen:** a standard iOS chat layout — scrollable message bubbles (user
right-aligned, assistant left-aligned), a text field + send button pinned to
the bottom, a "Coach is thinking…" indicator while a call is in flight. Older
messages beyond the rolling window simply aren't in `ChatMessageModel`
anymore (folded into the summary) — the transcript view only ever needs to
render what's actually persisted, so no separate "load more" affordance is
needed for Part 1.

## 6. Non-goals for this part

- **Proposing changes** (exercise swaps, set/load adjustments, routine
  revisions) — needs the suggestion-card component and
  `PendingCoachSuggestion` model (Part 2) and, for permanent routine changes,
  a Plan-review screen (Part 3).
- **Streaming responses** — no provider in this codebase supports it; adding
  it would be its own cross-provider infrastructure change.
- **`schedule_reminder`** — ties into the notifications/scheduling subsystem,
  a separate later item on the overall roadmap.

## Self-review

- **Placeholder scan:** no TBDs; every new type has concrete fields, every
  new behavior has a concrete trigger and failure mode.
- **Consistency:** the chat coordinator's failure handling is deliberately
  *different* from finalize/memory-keeper's "always silent" contract, and
  that difference is explained (a chat message is visibly present, so silent
  failure would be confusing rather than safe) — not an inconsistency, a
  distinct design choice for a distinct surface.
- **Scope:** this is Part 1 of 3 for Ask Coach, itself item 3 of the six-item
  roadmap from the original "AI Coach Layer" ask. Parts 2 (suggestion cards +
  `PendingCoachSuggestion`) and 3 (Plan-review screen for routine revisions)
  are named but not designed here — each gets its own spec once this part is
  built and working.
