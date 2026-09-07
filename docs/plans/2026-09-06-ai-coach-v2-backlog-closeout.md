# AI Coach Layer v2 — Backlog Closeout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development`. One fresh
> implementer per task, task review after each, whole-branch review + fix wave at the end.

**Goal:** Close every deferred/ledgered item from the AI Coach Layer v2 build so the branch
`fitness-engine-v2` is feature-complete and ready for simulator testing + merge.

**Architecture:** Six independent tasks. Task 1 touches a shared file (`ToolLoopRunner.swift`) plus
every coordinator's catch block. Tasks 2–3 touch `FitnessCore/CoachMemory` public types + the app's
memory models and tools. Tasks 4–5 are proactive-notification fixes. Task 6 is the review gate.

**Tech Stack:** Swift 6 `.v6`, Xcode 26 (`@MainActor` default isolation), SwiftData, Swift Testing,
`FitnessCore` local package (`CoachMemory`, `LLMKit`, `FitnessDomain`).

**Specs this argues from:**
- `docs/specs/2026-09-05-ai-coach-layer-v2-design.md` §5.2(3) — the MemoryOutcome loop (Task 3).
- `docs/specs/2026-09-05-plan-memory-and-routine-revisions-design.md` — routine-revision writes (Task 2).
- `.superpowers/sdd/2026-09-06-proactive-notifications/final-review.md` and `re-review-1.md` —
  the source of items I2, I4, M2, M5, N3–N6 (Tasks 1, 4, 5). Each finding there carries a "Fix:"
  block; this plan copies the intended fix, the review doc has the rationale.

## Global Constraints

- Xcode 26 default `@MainActor` isolation for the app module. `nonisolated` on pure value types
  (`ProactiveSettings`, DTOs) stays. `FitnessCore` types are not `@MainActor`.
- NEVER a boolean `#Predicate` in a SwiftData `@Query` — plain `@Query` + Swift-side `.filter`.
- Do NOT use `removeAllPendingNotificationRequests()` — scope every removal to identifiers.
- One `AICallRecord` per underlying `LLMProvider.complete` call (call-granular).
- New `@Model` fields are additively lightweight-migrated; no versioned schema in this project.
- No real network in tests. Plain commit messages, NO `Co-Authored-By` trailer.
- End state: `xcodebuild test -project FitnessTracker/FitnessTracker.xcodeproj -scheme FitnessTracker
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` green (the `FitnessTrackerUITests`
  `SBMainWorkspace ... Busy` parallel-launch flake is known; verify that bundle alone after
  `xcrun simctl shutdown all` if the combined run trips it).

---

## Task 1: `ToolLoopError.providerFailed(calls:)` — stop losing partial billing (I4)

**Files:**
- Modify: `FitnessTracker/FitnessTracker/AI/ToolLoopRunner.swift`
- Modify: `FitnessTracker/FitnessTracker/AI/MemoryKeeperCoordinator.swift` (~:73–85)
- Modify: `FitnessTracker/FitnessTracker/AI/ChatSummarizer.swift` (~:48–58)
- Modify: `FitnessTracker/FitnessTracker/AI/AskCoachCoordinator.swift` (~:58–74)
- Modify: `FitnessTracker/FitnessTracker/AI/SessionFinalizeCoordinator.swift` (~:70–95)
- Modify: `FitnessTracker/FitnessTracker/AI/ProactiveCoordinator.swift` (4 sites: ~:83–95, ~:202–231, ~:269–279, ~:315–342)
- Test: `FitnessTracker/FitnessTrackerTests/ToolLoopRunnerTests.swift` (create or extend)

**Problem:** `ToolLoopRunner.run` lets `provider.complete` errors propagate raw. Its local
`var calls` — which may already hold several *successful, billed* `CallOutcome`s from earlier
tool-loop iterations — is discarded, and every call site's bare `catch { … }` records nothing. A
4-iteration loop that succeeds on calls 1–3 and fails on call 4 writes **zero** `AICallRecord`s.

**Interfaces produced:**
- `ToolLoopError.providerFailed(calls: [CallOutcome])` — new case, alongside
  `.exceededMaxIterations(calls:)`.
- `ToolLoopRunner.run` still `throws`; on a `provider.complete` failure it now throws
  `.providerFailed(calls:)` with all outcomes accumulated so far, the last one
  `CallOutcome(inputTokens: 0, outputTokens: 0, cachedTokens: 0, succeeded: false)`.

- [ ] **Step 1: Failing test** — `providerFailureCarriesPriorCallsForBilling`

```swift
@Test func providerFailureCarriesPriorCallsForBilling() async throws {
    // A stub that returns one valid tool-call turn, then throws on the 2nd complete().
    let provider = SequenceThrowingProvider(
        firstTurn: #"{"decision":"toolCall","toolCall":{"name":"noop","argsJSON":"{}"}}"#)
    let tools = ToolRegistry(tools: [NoopTool()])
    do {
        let _: ToolLoopResult<DummyFinal> = try await ToolLoopRunner().run(
            system: "s", initialUser: "u", finalSchema: DummyFinal.schema,
            tools: tools, provider: provider, maxIterations: 4)
        Issue.record("expected throw")
    } catch let ToolLoopError.providerFailed(calls) {
        #expect(calls.count == 2)
        #expect(calls[0].succeeded == true)
        #expect(calls[1].succeeded == false)
    }
}
```

Provide `SequenceThrowingProvider`, `NoopTool`, `DummyFinal` as small local test fixtures if the
target lacks them (search the test target first — `StubLLMProvider` and the `ToolLoopTurn`
envelope `{"decision":"final","final":{…}}` already exist and may be enough with a
`responses: [.success(turn), .failure(SomeError())]` sequence if `StubLLMProvider` supports it;
if it does, use it instead of a new fixture).

- [ ] **Step 2: Run it — fails** (no `providerFailed` case).

- [ ] **Step 3: Implement in `ToolLoopRunner.run`**

```swift
for _ in 0..<maxIterations {
    let result: LLMResult<ToolLoopTurn<Final>>
    do {
        result = try await provider.complete(
            system: system, user: user, schema: schema, as: ToolLoopTurn<Final>.self)
    } catch {
        calls.append(CallOutcome(inputTokens: 0, outputTokens: 0, cachedTokens: 0, succeeded: false))
        throw ToolLoopError.providerFailed(calls: calls)
    }
    calls.append(CallOutcome(inputTokens: result.inputTokens, outputTokens: result.outputTokens,
                             cachedTokens: result.cachedTokens, succeeded: true))
    // …unchanged switch on result.value…
}
```

(Match the real return type of `provider.complete` — inspect `LLMProvider` in `LLMKit`; the binding
above is illustrative. Keep the existing `calls.append(...succeeded: true)` for the success path.)

Add the enum case:

```swift
enum ToolLoopError: Error, Sendable, Equatable {
    case exceededMaxIterations(calls: [CallOutcome])
    case providerFailed(calls: [CallOutcome])
}
```

- [ ] **Step 4: Thread it through every call site.** Each site that has
`catch ToolLoopError.exceededMaxIterations(let calls) { recordCalls(calls, …) }` gets an identical
sibling:

```swift
} catch ToolLoopError.exceededMaxIterations(let calls) {
    recordCalls(calls, callType: "…")           // unchanged
} catch ToolLoopError.providerFailed(let calls) {
    recordCalls(calls, callType: "…")           // NEW — same callType string as the success path
} catch { return }                              // or the site's existing bare catch
```

Exact sites and their `callType` / recorder:
- `MemoryKeeperCoordinator` — `recordCalls(partialCalls)` style; mirror it.
- `ChatSummarizer` — same.
- `AskCoachCoordinator` — `recordCalls(partialCalls)`, then still `return AskCoachReply(text: "Coach couldn't respond — try again.", isError: true)`.
- `SessionFinalizeCoordinator` — `recordCalls(calls, usedFallback:)` — pass the same args the
  `exceededMaxIterations` branch passes.
- `ProactiveCoordinator` ×4 — `recordCalls(calls, callType: "dailyNarration" | "weeklySummary" | "patternNudge" | "checkinReaction")`.

`CallOutcome` already has `succeeded`; `recordCalls` in `ProactiveCoordinator` already maps it to
`AICallRecord(success:)`, so the failed outcome lands as a `success: false` row — verify the other
recorders do too (they should; if one ignores `succeeded`, leave that untouched — out of scope).

- [ ] **Step 5: Run full unit bundle — green. Commit.**

```
git commit -m "ToolLoopRunner: preserve accumulated billing on provider failure

Add ToolLoopError.providerFailed(calls:) and wrap provider.complete so a
tool loop that fails after >=1 billed sub-call still hands its CallOutcomes
to the caller. Every coordinator catch block that already handles
exceededMaxIterations now handles providerFailed the same way."
```

---

## Task 2: Routine-revision memory — source attribution + dedup (plan-memory I1, I2)

**Files:**
- Modify: `FitnessCore/Sources/CoachMemory/MemoryConsolidation.swift`
- Modify: `FitnessTracker/FitnessTracker/AI/Tools/RoutineRevisionTool.swift`
- Test: `FitnessCore/Tests/CoachMemoryTests/MemoryConsolidationTests.swift`
- Test: `FitnessTracker/FitnessTrackerTests/RoutineRevisionToolTests.swift` (extend)

**Problem (I2):** `MemoryConsolidation.reconcile`'s `freshMemory(from:)` hard-codes
`source: .agent("memoryKeeper")` for *every* candidate. A preference the athlete stated directly in
Ask Coach via `propose_routine_revision` is indistinguishable from an LLM inference off a session log.

**Problem (I1):** `ProposeRoutineRevisionTool.run` always builds `MemoryCandidate(… relation: .new)`.
Say "I want more shoulder volume" in two separate chats → two near-identical `preference` rows
instead of one reinforced row. `reconcile` trusts the caller's `relation` and has no fuzzy matching.

**Interfaces produced:**
- `MemoryCandidate.source: MemorySource` — new stored property, **defaulted** in `init` to
  `.agent("memoryKeeper")` so all existing call sites compile unchanged.
- `MemoryConsolidation.reconcile` gains `dedupeNewAgainstExisting: Bool = false`. When `true`, a
  `.new` candidate whose `normalizedStatement` exactly equals that of a live (not retired, not
  cap-retired, not superseded) existing memory **of the same kind** is treated as
  `.reinforces(existing.id)` instead of creating a row. `normalizedStatement` =
  `statement.lowercased()` with runs of whitespace collapsed to one space and leading/trailing
  whitespace + a trailing `.` trimmed. Conservative on purpose — exact normalized equality only,
  no token-overlap heuristic (that risks merging distinct preferences).

- [ ] **Step 1: Failing tests (FitnessCore)**

```swift
@Test func newCandidateReinforcesAnExistingIdenticalStatementWhenDedupeOn() {
    let existing = CoachMemory(id: UUID(), kind: .preference,
        statement: "Wants more shoulder volume on push days", action: nil,
        confidence: 0.6, source: .user, createdAt: .now, lastConfirmedAt: .now,
        supersededBy: nil, tags: MemoryTags(), outcomeScore: nil, retiredByCap: false)
    let cand = MemoryCandidate(kind: .preference,
        statement: "  wants more shoulder volume on push days.  ", action: nil,
        tags: MemoryTags(), relation: .new, source: .user)
    let r = MemoryConsolidation.reconcile(existing: [existing], candidates: [cand],
        now: .now, dedupeNewAgainstExisting: true)
    #expect(r.writes.isEmpty)
    #expect(r.updated.count == 1)
    #expect(r.updated[0].id == existing.id)
    #expect(r.updated[0].confidence > 0.6)
}

@Test func newCandidateStillWritesWhenDedupeOffOrNoMatch() {
    // dedupe off => unchanged legacy behaviour (one write, no update)
    let cand = MemoryCandidate(kind: .preference, statement: "Prefers morning sessions",
        action: nil, tags: MemoryTags(), relation: .new, source: .user)
    let r = MemoryConsolidation.reconcile(existing: [], candidates: [cand], now: .now)
    #expect(r.writes.count == 1)
    #expect(r.writes[0].source == .user)   // source threaded through
}
```

- [ ] **Step 2: Run — fails** (`source:` param doesn't exist; `dedupeNewAgainstExisting:` doesn't exist).

- [ ] **Step 3: Implement**

`MemoryCandidate`:

```swift
public let source: MemorySource
public init(kind: MemoryKind, statement: String, action: String?, tags: MemoryTags,
            relation: CandidateRelation, source: MemorySource = .agent("memoryKeeper")) {
    …; self.source = source
}
```

`reconcile`: add `dedupeNewAgainstExisting: Bool = false` param. In `freshMemory(from:)` use
`source: candidate.source` instead of the literal. Add a private
`normalized(_ s: String) -> String`. In the `case .new:` branch, when
`dedupeNewAgainstExisting`, first look for
`existing.first { $0.kind == candidate.kind && !$0.isRetired && !$0.retiredByCap
  && $0.supersededBy == nil && normalized($0.statement) == normalized(candidate.statement) }`
— if found, run the exact same body as `case .reinforces(match.id)` (bump confidence, set
`lastConfirmedAt`, fill `action` if nil, `consumedExistingIDs.insert`, `updated.append`) and
`continue`; else fall through to the current `writes.append(freshMemory(...))`.

- [ ] **Step 4: `ProposeRoutineRevisionTool`** — build the candidate with
`source: .user` (the athlete stated it) and call
`MemoryConsolidation.reconcile(existing:candidates:now:newConfidence: 0.6, dedupeNewAgainstExisting: true)`.
Everything else in that method (persisting `writes` + walking `updated + retired`) is unchanged and
already correct.

- [ ] **Step 5: Extend `RoutineRevisionToolTests`** — add a test that calling the tool twice with
the same statement leaves exactly one `CoachMemoryModel` of kind `preference`, with
`confidence > 0.6` after the second call, and `source` persisted as `.user` (check
`CoachMemoryModel` maps `MemorySource` — it does, via `ModelSnapshotMapping`).

- [ ] **Step 6: `FitnessCore` tests + app unit bundle green. Commit.**

```
git commit -m "CoachMemory: candidate source attribution + opt-in new-vs-existing dedup

MemoryCandidate carries its own MemorySource (default unchanged). reconcile
gains dedupeNewAgainstExisting so a repeated athlete-stated preference
reinforces the existing row instead of piling up near-duplicates.
propose_routine_revision now writes source: .user with dedupe on."
```

---

## Task 3: Close the MemoryOutcome loop (spec §5.2.3)

**Files:**
- Modify: `FitnessTracker/FitnessTracker/Models/PendingCoachSuggestion.swift`
- Modify: `FitnessTracker/FitnessTracker/AI/Tools/SuggestionTools.swift` (`ProposeExerciseSwapTool`, `ProposeSetChangeTool`)
- Modify: `FitnessTracker/FitnessTracker/AI/AskCoachPromptBuilder.swift` (system prompt hint)
- Modify: `FitnessTracker/FitnessTracker/AI/SuggestionApplier.swift`
- Test: `FitnessTracker/FitnessTrackerTests/SuggestionApplierTests.swift` (extend)
- Test: `FitnessTracker/FitnessTrackerTests/SuggestionToolsTests.swift` (extend)

**Spec §5.2(3):** "When a suggestion built from a memory is accepted and works out (or is
rejected), that should write back to the memory's `outcomeScore` — so a bad suggestion pattern
actually stops recurring instead of only fading passively via recency decay."

`FitnessCore/Sources/CoachMemory/MemoryOutcome.swift` already provides
`MemoryOutcome.applyResult(to:signal:weight:) -> CoachMemory` with
`OutcomeSignal { .improved, .unchanged, .worse }`. Nothing in the app calls it.

**Design (ruled — pragmatic faithful MVP):** the signal is accept vs. skip, not a full
through-the-next-session outcome measurement (that needs infrastructure out of scope here).
`weight` stays low (`0.3` default) so one accept/skip nudges rather than dominates.

**Interfaces produced:**
- `PendingCoachSuggestion.sourceMemoryID: UUID?` — new optional `@Model` field, `nil` in `init`.
- `ProposeExerciseSwapTool` / `ProposeSetChangeTool` args gain optional `sourceMemoryId: String?`
  (a UUID string the model copies from a `[uuid]`-prefixed line in the memory digest). When present
  and parseable, set it on the created `PendingCoachSuggestion`.
- `SuggestionApplier.apply(_:storedPlan:)` and `SuggestionApplier.skip(_:)` — after their existing
  work, if `suggestion.sourceMemoryID != nil`, look up the `CoachMemoryModel`, compute
  `MemoryOutcome.applyResult(to: model.toDomain(), signal: accepted ? .improved : .worse)`, write
  the returned `outcomeScore` back onto the model. Needs a `ModelContext` — `apply`/`skip` are
  currently static and take no context; add a `context: ModelContext` parameter (update the 2–3
  call sites in `HomeView` / `SuggestionCard`).

- [ ] **Step 1: Failing tests**

```swift
@Test func acceptingAMemoryBackedSuggestionRaisesOutcomeScore() throws {
    let ctx = ModelContext(try container())
    let mem = CoachMemoryModel(/* kind preference, confidence 0.6, outcomeScore nil */)
    ctx.insert(mem)
    let plan = /* seed a StoredPlan with one not-started session + one item */
    let sugg = PendingCoachSuggestion(plannedSessionID: sid, kind: "setChange",
        exerciseID: exId, rationale: "you said you want more shoulder volume", source: "askCoach")
    sugg.sourceMemoryID = mem.id
    sugg.targetSets = 4
    ctx.insert(sugg); try ctx.save()
    try SuggestionApplier.apply(sugg, storedPlan: stored, context: ctx)
    try ctx.save()
    #expect((mem.outcomeScore ?? 0) > 0)
}

@Test func skippingAMemoryBackedSuggestionLowersOutcomeScore() throws {
    // …same setup… SuggestionApplier.skip(sugg, context: ctx)
    #expect((mem.outcomeScore ?? 0) < 0)
}

@Test func proposeSetChangeStoresSourceMemoryIdWhenGiven() {
    // ProposeSetChangeTool.run with argsJSON including "sourceMemoryId":"<uuid>"
    // => the written PendingCoachSuggestion has sourceMemoryID == that uuid
}
```

- [ ] **Step 2: Run — fails.**

- [ ] **Step 3: Implement the field + tool args + applier.** For the applier signal: `.improved`
on accept, `.worse` on skip (not `.unchanged` — skip is a real negative signal here). Clamp is
handled inside `applyResult`/`CoachMemory.init`. If the memory row is gone (superseded/evicted),
skip silently.

- [ ] **Step 4: Prompt hint** in `AskCoachPromptBuilder.system()` — one sentence: *"When a
`propose_*` call is driven by something you remember about this athlete (a `[uuid]` line in the
memory list), pass that uuid as `sourceMemoryId` so the coach can learn whether that suggestion
lands."*

- [ ] **Step 5: Update `SuggestionApplier` call sites** to pass `context`. Grep
`SuggestionApplier.apply` / `.skip` — `HomeView.swift` `onAccept`/`onSkip` closures and any
`SuggestionCard` usage. `context` is the `@Environment(\.modelContext)` already in scope.

- [ ] **Step 6: Unit bundle green. Commit.**

```
git commit -m "Close the MemoryOutcome loop for memory-backed suggestions

PendingCoachSuggestion carries an optional sourceMemoryID; the Ask Coach
propose tools set it from the cited [uuid] in the memory digest.
SuggestionApplier.apply/skip now feed MemoryOutcome.applyResult so an
accepted suggestion raises, and a skipped one lowers, the source memory's
outcomeScore (spec section 5.2)."
```

---

## Task 4: Cold-launch notification tap — assign the delegate in an AppDelegate (proactive I2)

**Files:**
- Create: `FitnessTracker/FitnessTracker/AppDelegate.swift`
- Modify: `FitnessTracker/FitnessTracker/FitnessTrackerApp.swift`
- Modify: `FitnessTracker/FitnessTracker/RootView.swift` (remove the `.task` delegate assignment)

**Problem:** `RootView.swift`'s `.task` sets
`UNUserNotificationCenter.current().delegate = notificationResponder` *after* first render, which is
after `application(_:didFinishLaunchingWithOptions:)` returns. A tap on `proactive_weekly` that
cold-launches the app hits `didReceive` with no delegate installed, so `showWeeklySummary` never
flips and the recap sheet never presents. The in-app path works; the killed-app path is the exact
scenario the feature exists for.

**Design:** a single shared `NotificationResponder` instance owned by an `AppDelegate`, assigned as
the `UNUserNotificationCenter` delegate in `didFinishLaunchingWithOptions`. `RootView` observes the
*same* instance (injected via `@EnvironmentObject` or read from the app delegate).

**Interfaces produced:**
- `final class AppDelegate: NSObject, UIApplicationDelegate` with
  `let notificationResponder = NotificationResponder()` and
  `application(_:didFinishLaunchingWithOptions:) -> Bool` that does
  `UNUserNotificationCenter.current().delegate = notificationResponder; return true`.
- `FitnessTrackerApp` gains `@UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate`
  and injects `appDelegate.notificationResponder` into the environment:
  `WindowGroup { RootView() }.environmentObject(appDelegate.notificationResponder)`.
- `RootView` replaces `@StateObject private var notificationResponder = NotificationResponder()`
  with `@EnvironmentObject private var notificationResponder: NotificationResponder`, and DELETES
  the `UNUserNotificationCenter.current().delegate = notificationResponder` line from its `.task`.
  Everything else in `RootView` (`.sheet(isPresented: $notificationResponder.showWeeklySummary)`)
  is unchanged.

**Notes:**
- `NotificationResponder` is already `@MainActor final class … ObservableObject … UNUserNotificationCenterDelegate`
  with `nonisolated` delegate methods — no change to it.
- `AppDelegate` needs `import UIKit` + `import UserNotifications`.
- Keep the `willPresent` filter (`userInfo["proactive"] != nil`) exactly as it is.
- `Previews`/tests that instantiate `RootView()` directly will now need the environment object —
  grep for `RootView(` in the test target and previews; add `.environmentObject(NotificationResponder())`
  where needed, or leave `RootView` with a fallback `@StateObject` if that proves cleaner. Prefer
  the `@EnvironmentObject` route; only fall back if a preview/test genuinely can't supply it.

- [ ] **Step 1** — create `AppDelegate.swift`.
- [ ] **Step 2** — wire `@UIApplicationDelegateAdaptor` + `.environmentObject` in `FitnessTrackerApp`.
- [ ] **Step 3** — switch `RootView` to `@EnvironmentObject`, delete the `.task` assignment line.
- [ ] **Step 4** — build; fix any `RootView(` construction site missing the environment object.
- [ ] **Step 5** — full test bundle green (unit + UI-alone if the combined run flakes). Commit.

```
git commit -m "Assign the notification delegate in an AppDelegate for cold-launch taps

A tapped proactive_weekly notification that cold-launches the app now
reaches a delegate that was installed in didFinishLaunchingWithOptions
instead of a SwiftUI .task that runs after that point. One shared
NotificationResponder, owned by the AppDelegate, observed by RootView."
```

---

## Task 5: Proactive-notification small fixes bundle (M2, M5, N3, N4, N5, N6)

**Files:**
- Modify: `FitnessTracker/FitnessTracker/AI/ProactiveCoordinator.swift` (M2, N4)
- Modify: `FitnessTracker/FitnessTracker/Features/Stats/WeeklySummaryView.swift` (N3, N5)
- Modify: `FitnessTracker/FitnessTracker/Features/Settings/SettingsView.swift` (N6)
- Modify: `FitnessTracker/FitnessTracker/AI/ProactiveCoordinator.swift` + `Features/Home/HomeView.swift` (M5)
- Test: `FitnessTracker/FitnessTrackerTests/ProactiveCoordinatorTests.swift` (extend for M2)

Each item is independent; do them in any order, one commit for the bundle.

### M2 — orphaned `proactive.patternNudge.<uuid>` UserDefaults keys grow forever
In `ProactiveCoordinator.runPatternNudges()`, after fetching the live `responsePattern`
`CoachMemoryModel`s, sweep: build `let liveIDs = Set(allResponsePatternMemories.map { $0.id.uuidString })`
(fetch ALL `responsePattern` rows, not just the ≥0.6 candidates — a memory that dropped below 0.6
is still live and its key should stay). For every `UserDefaults.standard.dictionaryRepresentation()`
key with prefix `"proactive.patternNudge."`, if the suffix isn't in `liveIDs`,
`removeObject(forKey:)`. Add a test: seed two `patternNudge` keys, one for a real memory and one
for a random UUID; run `runDueChecks` with `patternOn` (provider nil is fine — the sweep must run
before the `guard provider != nil`, so move the sweep into a small helper called unconditionally
when `settings.patternOn`, OR run it at the top of `runPatternNudges` accepting that a nil provider
skips it — pick the former so the test needs no provider). Assert the orphan key is gone, the real
one remains.

### M5 — weekly `CoachNoteModel` duplicates the Home `thisWeekCard`
Spec §4#7 wants both a notification and a Home surface, but `thisWeekCard` already IS a persistent
Home surface and the `CoachNoteModel(kindRaw: "weekly", text: dto.headline)` shows the identical
headline in a second card until "Got it". **Ruling:** keep the weekly `CoachNoteModel` (spec-
mandated, and it's the only Home surface when the `WeeklySummaryModel` query hasn't refreshed) but
give it *complementary* text — use `dto.nextWeekFocus` instead of `dto.headline`:
`context.insert(CoachNoteModel(kindRaw: "weekly", text: "Next week: \(dto.nextWeekFocus)"))`.
Now the note ("Next week: …") and the card (headline) say different things. No HomeView change
needed beyond confirming `thisWeekCard` still renders from `WeeklySummaryModel`.

### N3 — after upgrade, a pre-existing `WeeklySummaryModel` stamped on the *current* week
shows under the new "Last week" header for one week.
In `WeeklySummaryView`, the `summaries` `@Query` is sorted `weekStartDate` desc. Filter the
displayed summary to one whose `weekStartDate` is strictly before the current ISO week start:

```swift
private var displayed: WeeklySummaryModel? {
    guard let currentWeekStart = Calendar.isoUTC.dateInterval(of: .weekOfYear, for: .now)?.start
    else { return summaries.first }
    return summaries.first { $0.weekStartDate < currentWeekStart }
}
```

Use `displayed` everywhere the view currently uses `summaries.first`; `emptyState` shows when
`displayed == nil`.

### N4 — `scheduleInBodyReminderIfNeeded` spawns a detached `Task` that escapes the I1
`isRunning` guard.
Currently it's `notificationCenter.getPendingNotificationRequests { … }` (completion handler) or a
detached `Task`. Make it `async` and `await` it inside `runDueChecks` so it's inside the
`isRunning` critical section:

```swift
private func scheduleInBodyReminderIfNeeded() async {
    let pending = await notificationCenter.pendingNotificationRequests()
    guard !pending.contains(where: { $0.identifier == "proactive_inbody" }) else { return }
    installInBodyReminder()
}
```

and `runDueChecks` calls `await scheduleInBodyReminderIfNeeded()`. `resetInBodyReminder()` stays
synchronous and unconditional (calls `installInBodyReminder()` directly) — unchanged.

### N5 — `WeeklySummaryView.currentStreakWeeks` uses `now: .now` under a "Last week" header.
Pass the displayed summary's week instead:
`StreakCalculator.computeSummary(from: finishedSessions.map { $0.toSnapshot() }, plannedPerWeek: 3,
now: displayed?.weekStartDate.addingTimeInterval(6*86400) ?? .now).currentStreakWeeks`
— i.e. evaluate the streak as of the end of the covered week, so all three stat rows describe the
same week. (If `StreakCalculator.computeSummary`'s `now` param doesn't accept a past date cleanly,
leave `currentStreakWeeks` as-is and add a one-line `// as-of-today` comment — don't fight the API.)

### N6 — `SettingsView.notifAuthorized` sampled once in `.task`, goes stale after the user
grants permission in iOS Settings and returns.
Add `@Environment(\.scenePhase) private var scenePhase` and re-sample on `.active`:

```swift
.onChange(of: scenePhase) { _, phase in
    guard phase == .active else { return }
    Task {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notifAuthorized = (status == .authorized || status == .provisional || status == .ephemeral)
    }
}
```

- [ ] Implement all six. Full unit bundle green (+ UI-alone if combined flakes). One commit:

```
git commit -m "Proactive notifications: small correctness + polish fixes

M2 sweep orphaned proactive.patternNudge.* UserDefaults keys.
M5 weekly CoachNote now carries next-week focus, not a duplicate headline.
N3 WeeklySummaryView ignores a still-current-week row after upgrade.
N4 InBody pending-check is awaited inside the runDueChecks guard.
N5 weekly streak row evaluated as of the covered week.
N6 Settings re-samples notification authorization on foreground."
```

---

## Task 6: Whole-branch review + fix wave (gate)

Not an implementer task — the controller runs this per `subagent-driven-development`:

1. `review-package docs/plans/2026-09-06-ai-coach-v2-backlog-closeout.md ce8270c HEAD` (BASE =
   the proactive-notifications branch tip before this plan started — confirm with `git log`).
2. Dispatch the whole-branch reviewer on the most capable model, focused on: did I4's new catch
   arms actually get added at ALL eight sites; does the Task 2 dedupe ever merge two *distinct*
   preferences (false-positive normalization); is `sourceMemoryID` ever set but the memory lookup
   silently no-ops in `SuggestionApplier`; does the `AppDelegate` change break any `RootView(`
   construction in previews/tests; does N4's `async` change alter `runDueChecks` ordering.
3. One fix dispatch, one scoped re-review, adjudicate residuals.
4. Final full `xcodebuild test` (unit bundle + UI bundle run alone).
5. Update `docs/HANDOFF.md`: new "AI Coach Layer v2 — complete" subsection under §2, bump the test
   counts in §3, and add to the gotchas list: *"`DateFormatter.calendar` does NOT set
   `DateFormatter.timeZone` — a formatter with `.calendar = .isoUTC` still emits local-time strings
   unless `.timeZone` is set explicitly."* (This file has unrelated uncommitted edits from the
   user — stage only the HANDOFF hunks this task adds, via `git add -p`, or ask the user first.)
6. Report the branch as ready for simulator testing + merge.

---

## Self-Review

- **Spec coverage:** I4/I2(proactive)/M2/M5/N3–N6 ← proactive review docs (Tasks 1,4,5). Plan-memory
  I1/I2 ← Task 2. §5.2(3) MemoryOutcome ← Task 3. Everything ledgered is assigned. Nightly-batch
  memory-keeper is explicitly NOT in scope — it was a conversational idea, never a spec item (spec
  §5.2.1 names "per finished session" + "after an Ask Coach exchange", both already built).
- **Type consistency:** `ToolLoopError.providerFailed(calls:)` mirrors `.exceededMaxIterations(calls:)`
  exactly. `MemoryCandidate.source` defaulted so no existing caller breaks. `PendingCoachSuggestion`
  `.sourceMemoryID` optional so existing rows migrate clean. `SuggestionApplier` signature change is
  the one breaking change — Task 3 Step 5 handles its call sites.
- **Placeholder scan:** the test bodies in Tasks 2–3 have `/* … */` seed comments — implementers
  must write real seeds (the surrounding assertions are concrete). Flagged here deliberately; the
  seed helpers (`container()`, `seedPlan`) already exist in those test files.
