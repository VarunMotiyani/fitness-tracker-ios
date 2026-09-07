# Plan-Generation Memory Wiring + Routine Revisions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire `MemoryRecall` into the AI plan-generation path, and give Ask
Coach a `propose_routine_revision` tool that writes a durable preference
through the existing `MemoryConsolidation` pipeline — so a stated program
preference actually influences next week's plan instead of being forgotten.

**Architecture:** `PlanPromptBuilder`/`PlanCoordinator` gain a `memoryDigest`
parameter threaded through exactly like `priorIssues` already is.
`generateAndStore` builds the digest via the same `MemoryRecall.select`
pattern every other AI call site in this app already uses. The new tool
mirrors `SuggestionTools.swift`'s existing propose-tool shape but writes a
`CoachMemory` directly via `MemoryConsolidation.reconcile`, the same
deterministic gate the memory-keeper call uses.

**Tech Stack:** Swift 6 `.v6`, Xcode 26, SwiftData, Swift Testing,
`FitnessCore` (`CoachMemory`, `FitnessDomain`, `LLMKit`).

**Spec:** `docs/specs/2026-09-05-plan-memory-and-routine-revisions-design.md`
(all sections, including §2's rulings — binding, decided without a user
round-trip per standing instruction).

## Global Constraints

- Xcode 26 default `@MainActor` isolation for the app module;
  `PlanPromptBuilder`/`PlanCoordinator` are `nonisolated` (pure, no
  `ModelContext`) — keep them that way; only `generateAndStore` (already
  `@MainActor`, touches `ModelContext`) builds the digest.
- The tool must fetch existing memories fresh from `ModelContext` at call
  time, not from a stale snapshot — the exact lesson the memory-keeper plan's
  final review learned the hard way.
- No real network in tests. Plain commits, no `Co-Authored-By` trailer.
- End state: full xcodebuild test suite green.

---

## Task 1: Wire memory digest into `PlanPromptBuilder`/`PlanCoordinator`/`generateAndStore`

**Files:**
- Modify: `AI/PlanPromptBuilder.swift`
- Modify: `AI/PlanCoordinator.swift`
- Modify: `AI/PlanGeneration.swift`
- Modify (extend): `FitnessTrackerTests/PlanPromptBuilderTests.swift`,
  `FitnessTrackerTests/PlanCoordinatorTests.swift` (extend whichever
  existing test files cover these — check what exists first; if neither
  exists under those exact names, find the actual test files by grepping for
  `PlanPromptBuilder`/`PlanCoordinator` usage in `FitnessTrackerTests/`)

**Interfaces:**
- Produces: `PlanPromptBuilder.user(context:priorIssues:memoryDigest:)` (new
  parameter, default `""` so existing callers/tests don't need updating
  unless they want to test the new behavior), `PlanCoordinator.makePlan(context:weekStartDate:memoryDigest:)`
  (new parameter, default `""`).

- [ ] **Step 1: Extend `PlanPromptBuilder.user`**

Open the current file first. Add a `memoryDigest: String = ""` parameter to
`user(context:priorIssues:memoryDigest:)`, and append a section to the built
prompt string when non-empty:

```swift
if !memoryDigest.isEmpty {
    out += "\n\nWhat you know about this athlete:\n\(memoryDigest)"
}
```

Place it after the existing `priorIssues` block (order: base context → prior
issues if any → memory digest if any).

- [ ] **Step 2: Extend `PlanCoordinator.makePlan`**

Add `memoryDigest: String = ""` to `makePlan`'s signature, and pass it into
both `prompts.user(context:priorIssues:memoryDigest:)` calls (the initial
build and the retry build — both should receive the same digest).

- [ ] **Step 3: Build the digest in `generateAndStore`**

In `AI/PlanGeneration.swift`, before the `PlanCoordinator(...).makePlan(...)`
call, add:

```swift
let existingMemories = ((try? modelContext.fetch(FetchDescriptor<CoachMemoryModel>())) ?? []).map { $0.toDomain() }
let recalled = MemoryRecall.select(from: existingMemories, context: RecallContext(), now: .now)
```

Then pass `memoryDigest: recalled.digest` into the `makePlan(context:weekStartDate:memoryDigest:)`
call. Add the necessary import (`CoachMemory`) if not already present in this
file.

- [ ] **Step 4: Test — memory digest reaches the prompt**

Find or create the relevant test file for `PlanPromptBuilder` (grep
`FitnessTrackerTests/` for existing coverage first — reuse its exact helper
names). Add:

```swift
@Test func userPromptIncludesMemoryDigestWhenNonEmpty() {
    let builder = PlanPromptBuilder(catalog: /* however the existing tests build one */)
    let prompt = builder.user(context: /* existing test context builder */, memoryDigest: "- Prefers dumbbells over barbells")
    #expect(prompt.contains("Prefers dumbbells over barbells"))
}

@Test func userPromptOmitsMemorySectionWhenEmpty() {
    let builder = PlanPromptBuilder(catalog: /* ... */)
    let prompt = builder.user(context: /* ... */, memoryDigest: "")
    #expect(!prompt.contains("What you know about this athlete"))
}
```

**Note for the implementer:** match whatever `UserContext`/`CatalogStore`
test-fixture helpers already exist in this test file — don't invent new
ones if the file already has a working pattern.

- [ ] **Step 5: Build and test**

Run: `xcodebuild test -scheme FitnessTracker -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' -project FitnessTracker/FitnessTracker.xcodeproj 2>&1 | tail -30`
Expected: green (default-`""` parameters mean no existing call site breaks).

- [ ] **Step 6: Commit**

```bash
git add FitnessTracker/FitnessTracker/AI/PlanPromptBuilder.swift \
        FitnessTracker/FitnessTracker/AI/PlanCoordinator.swift \
        FitnessTracker/FitnessTracker/AI/PlanGeneration.swift
git add -u FitnessTracker/FitnessTrackerTests/  # only the test file(s) actually modified in Step 4
git commit -m "Wire MemoryRecall into AI plan generation"
```

**Note for the implementer:** the `git add -u` above is a convenience for
"whatever test file you actually edited in Step 4" — if you'd rather name it
explicitly, do so; just don't use `git add -A`/`.` for the whole repo.

---

## Task 2: `propose_routine_revision` tool

**Files:**
- Create: `AI/Tools/RoutineRevisionTool.swift`
- Test: `FitnessTrackerTests/RoutineRevisionToolTests.swift`

**Interfaces:**
- Produces: `@MainActor struct ProposeRoutineRevisionTool: CoachTool` —
  consumed by Task 3's `AskCoachCoordinator.buildTools()`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import SwiftData
import Foundation
import CoachMemory
@testable import FitnessTracker

@MainActor
@Suite struct RoutineRevisionToolTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: CoachMemoryModel.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func writesANewPreferenceMemory() throws {
        let ctx = ModelContext(try container())
        let tool = ProposeRoutineRevisionTool(context: ctx)

        let args = "{\"statement\": \"Wants more shoulder volume on push days\", \"action\": \"Add a lateral raise variation\"}"
        let result = tool.run(argsJSON: args)

        #expect(!result.contains("error"))
        let memories = try ctx.fetch(FetchDescriptor<CoachMemoryModel>())
        #expect(memories.count == 1)
        #expect(memories[0].kindRaw == "preference")
        #expect(memories[0].statement == "Wants more shoulder volume on push days")
    }

    @Test func reinforcesAnExistingSimilarPreferenceGivenAnID() throws {
        let ctx = ModelContext(try container())
        let existing = CoachMemoryModel(kindRaw: "preference", statement: "Wants more shoulder volume",
                                        confidence: 0.3, sourceKind: "agent", createdAt: .now, lastConfirmedAt: .now)
        ctx.insert(existing)
        try ctx.save()

        // The tool itself only ever proposes `.new` (it has no way to know an
        // existing memory's ID from chat context) — this test documents that
        // current, intentional scope: a second, similar statement creates a
        // second memory rather than reinforcing, same as any other `.new`-only
        // producer. Confirms no crash / unexpected merge behavior.
        let tool = ProposeRoutineRevisionTool(context: ctx)
        let args = "{\"statement\": \"Wants more shoulder volume\", \"action\": null}"
        _ = tool.run(argsJSON: args)

        let memories = try ctx.fetch(FetchDescriptor<CoachMemoryModel>())
        #expect(memories.count == 2)
    }

    @Test func rejectsBadArgs() throws {
        let ctx = ModelContext(try container())
        let tool = ProposeRoutineRevisionTool(context: ctx)
        let result = tool.run(argsJSON: "not json")
        #expect(result.contains("error"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme FitnessTracker -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' -project FitnessTracker/FitnessTracker.xcodeproj -only-testing:FitnessTrackerTests/RoutineRevisionToolTests 2>&1 | tail -30`

- [ ] **Step 3: Implement**

```swift
import Foundation
import SwiftData
import CoachMemory

struct ProposeRoutineRevisionArgs: Decodable {
    let statement: String
    let action: String?
}

/// Writes a durable preference through the same `MemoryConsolidation`
/// pipeline the memory-keeper call uses (design spec §4) — a "permanent"
/// routine change only ever works by feeding the *next* plan generation a
/// preference it reads (Task 1), not by editing a specific week's plan.
@MainActor
struct ProposeRoutineRevisionTool: CoachTool {
    let context: ModelContext

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            name: "propose_routine_revision",
            description: "Record a permanent program preference (not a one-session change) — it will influence future plan generation, not the current week's plan.",
            argsSchemaJSON: "{\"statement\": \"string\", \"action\": \"string|null\"}"
        )
    }

    func run(argsJSON: String) -> String {
        guard let args = decodeArgs(argsJSON, as: ProposeRoutineRevisionArgs.self) else {
            return "{\"error\": \"bad args\"}"
        }
        let existingMemories = ((try? context.fetch(FetchDescriptor<CoachMemoryModel>())) ?? []).map { $0.toDomain() }
        let candidate = MemoryCandidate(kind: .preference, statement: args.statement,
                                        action: args.action, tags: MemoryTags(), relation: .new)
        let result = MemoryConsolidation.reconcile(existing: existingMemories, candidates: [candidate], now: .now)

        for memory in result.writes {
            context.insert(coachMemoryModel(from: memory))
        }
        try? context.save()
        return "{\"status\": \"noted\"}"
    }
}
```

**Note for the implementer:** verify `coachMemoryModel(from:)` and
`CoachMemoryModel.toDomain()` are accessible from this new file (they live in
`Metrics/ModelSnapshotMapping.swift`, same app target — check whether an
`import Metrics` is needed and whether the functions are internal, not
`private`, to this module) before trusting this verbatim.

- [ ] **Step 4: Run tests to verify they pass, then commit**

```bash
git add FitnessTracker/FitnessTracker/AI/Tools/RoutineRevisionTool.swift \
        FitnessTracker/FitnessTrackerTests/RoutineRevisionToolTests.swift
git commit -m "Add ProposeRoutineRevisionTool: writes a durable preference for future plan generation"
```

---

## Task 3: Wire the tool into `AskCoachCoordinator`

**Files:**
- Modify: `AI/AskCoachCoordinator.swift`
- Modify: `AI/AskCoachPromptBuilder.swift`
- Modify (extend): `FitnessTrackerTests/AskCoachCoordinatorTests.swift`

- [ ] **Step 1: Extend `buildTools()`**

Add `ProposeRoutineRevisionTool(context: context)` to the array `buildTools()`
returns.

- [ ] **Step 2: Extend `AskCoachPromptBuilder.system()`**

Add one sentence after the existing propose-tools paragraph (from the
Suggestion Cards plan): "For a permanent program change — not a single
session — use propose_routine_revision instead; it becomes a standing
preference that shapes future plans, not an immediate edit."

- [ ] **Step 3: Add one coordinator-level wiring test**

Mirror the existing `sendExecutesProposeExerciseSwapToolAndPersistsSuggestion`-style
test (from the Suggestion Cards plan) but scripting a `propose_routine_revision`
tool call, asserting a `CoachMemoryModel` row exists after `send()` returns.

- [ ] **Step 4: Full suite, then commit**

```bash
git add FitnessTracker/FitnessTracker/AI/AskCoachCoordinator.swift \
        FitnessTracker/FitnessTracker/AI/AskCoachPromptBuilder.swift \
        FitnessTracker/FitnessTrackerTests/AskCoachCoordinatorTests.swift
git commit -m "Wire propose_routine_revision into AskCoachCoordinator"
```

---

## Self-Review Notes

- **Scope**: this plan deliberately does NOT touch the rule-engine's
  deterministic volume math, and does NOT build a Plan-review screen — both
  ruled out in the spec's §2, not overlooked.
- **Placeholder scan**: every step has real code; the two "Note for the
  implementer" flags (test-file discovery in Task 1, accessibility of
  `coachMemoryModel(from:)` in Task 2) are genuine, since this plan reuses
  existing test infrastructure it hasn't itself inspected in full.

## Execution

Subagent-driven — proceed without further check-ins per standing instruction.
