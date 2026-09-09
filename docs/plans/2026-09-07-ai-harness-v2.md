# AI Harness v2 — Implementation Plan

**Goal:** Turn the AI layer into a real harness — capability-aware provider
selection, a native tool-calling lane for frontier models, breadth via
OpenRouter, and app-owned retry/fallback that never double-bills.

**Rationale / design:** `docs/10-ai-provider-architecture-and-options.md`. Short
version: keep `LLMProvider` as the contract; the two things that make it
fragile are (a) the seam is capability-blind so the code guesses per request,
and (b) `ToolLoopRunner` is single-lane, so Claude/GPT/Gemini run on the least
reliable path. Fix those, add OpenRouter for breadth, wrap a thin resilience
decorator. No package adopted as the contract.

**Branch:** `ai-harness-v2`, cut from `main` after `fitness-engine-v2` merges
(that merge carries commit `cf80e49`, the Groq/Qwen JSON Object Mode work this
builds on).

**Acceptance bar:** the compatibility benchmark in
`docs/10-ai-provider-architecture-and-options.md` §"Compatibility benchmark
before changing the contract" (request/response behavior, tool behavior,
provider matrix, fitness-domain invariants). Every unit adds its slice of that
suite. The fitness-domain invariants are non-negotiable: generated exercise
IDs exist in the catalog; plan mutations pass rule-engine validation; failed
calls are billed exactly once; fallback attempts preserve call-level usage
records.

**Global constraints:**
- Swift 6 `.v6` strict concurrency; Xcode 26 `@MainActor`-default isolation.
  `FitnessCore` (incl. `LLMKit`) types are NOT `@MainActor`; keep provider
  code `nonisolated`/`Sendable`.
- One `AICallRecord` per underlying HTTP call to a provider. Retries and
  fallbacks each write their own record; records from a non-primary attempt
  set `usedFallback: true`.
- NEVER a boolean `#Predicate` in a SwiftData `@Query` — plain `@Query` +
  Swift-side `.filter`.
- New `@Model` fields are additively lightweight-migrated (no versioned schema
  in this project).
- No real network in tests. Plain commit messages, no `Co-Authored-By`.
- End state: `swift test --package-path FitnessCore` green;
  `xcodebuild test -project FitnessTracker/FitnessTracker.xcodeproj -scheme
  FitnessTracker -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
  -only-testing:FitnessTrackerTests` green. (A first-pass flake in
  `ProactiveCoordinatorTests` predates this work — see "Known preexisting
  issues" at the end; do not try to fix it here.)

---

## Shared contract — code both sides build against

Land in **Unit 1** and referenced by every other unit. Written here so Unit 3
and Unit 5 can be specified precisely.

### `ProviderCapabilities` (new, `FitnessCore/Sources/LLMKit/ProviderCapabilities.swift`)

```swift
public struct ProviderCapabilities: Sendable, Equatable, Codable {
    public enum StructuredOutput: String, Sendable, Codable {
        case nativeJSONSchema   // provider enforces a real JSON Schema (OpenAI strict, Gemini responseSchema, Apple guided)
        case jsonObject         // provider guarantees valid JSON but not a schema (Groq json_object)
        case promptOnly         // no server-side JSON guarantee; rely on prompt + local decode/repair
    }
    public enum ToolCalling: String, Sendable, Codable {
        case native             // provider has a function/tool API we drive (OpenAI tools, Anthropic tools, Gemini functionDeclarations)
        case viaPrompt          // no reliable native tools; use the manual envelope loop
    }
    public var structuredOutput: StructuredOutput
    public var toolCalling: ToolCalling
    public var streaming: Bool
    public var vision: Bool
    public var maxContextTokens: Int          // 0 = unknown

    public init(structuredOutput: StructuredOutput, toolCalling: ToolCalling,
                streaming: Bool, vision: Bool, maxContextTokens: Int = 0) { … }
}
```

### `LLMProvider` gains one requirement

```swift
public protocol LLMProvider: Sendable {
    var capabilities: ProviderCapabilities { get }   // NEW
    func complete<Value: Decodable & Sendable>(system:user:schema:as:) async throws -> LLMResult<Value>
    func completeWithImage<Value: Decodable & Sendable>(...) async throws -> LLMResult<Value>
    // stream(...) added in Unit 6 as an extension with a default, NOT a new requirement
}
```

Each adapter returns a static default for its kind. `ProviderProfile` may
override individual fields (see Unit 1). Resolution order: profile override →
adapter default.

### `ProviderProfile` capability fields (Unit 1)

Add nullable override columns (nil = use adapter default):
`capStructuredOutputRaw: String?`, `capToolCallingRaw: String?`,
`capStreaming: Bool?`, `capVision: Bool?`, `capMaxContextTokens: Int?`,
and `fallbackProfileID: UUID?` (Unit 4 reads it).

### Default capability table (Unit 1 ships this in `LLMProviderFactory`)

| adapterKind | structuredOutput | toolCalling | streaming | vision |
|---|---|---|---|---|
| `openAICompatible` (generic) | `jsonObject` | `viaPrompt` | true | false |
| `openAICompatible` + host `api.openai.com` | `nativeJSONSchema` | `native` | true | true |
| `openRouter` (new, Unit 3) | `jsonObject` | `viaPrompt` | true | false |
| `gemini` | `nativeJSONSchema` | `native` | true | true |
| `vertexAI` | `nativeJSONSchema` | `native` | true | true |
| `bedrock` | `nativeJSONSchema` | `native` | true | true |
| `appleOnDevice` | `nativeJSONSchema` (after Unit 5) / `promptOnly` (before) | `viaPrompt` (native in Unit 5 if scoped) | false | false |

Model-family refinement (e.g. a DeepSeek model on OpenRouter that does support
native tools) is a Unit 3/future concern via the profile override, not the
default table.

### `AICallRecord` billing rule for the resilient path (Unit 4)

`ResilientProvider` writes nothing itself. Each wrapped `complete` call that
reaches the network produces exactly one `AICallRecord` at the point the
underlying adapter/coordinator already records it. Unit 4's job is to make
sure a fallback attempt's record carries `usedFallback: true` and that a
retry of the *same* provider still bills each attempt. The coordinators own
`recordCalls`; Unit 4 threads an `attemptIndex`/`isFallback` signal to them.

---

## Work split

| Unit | Owner | Depends on | Files (primary) |
|---|---|---|---|
| 1. Capability layer + factory defaults | **Claude** | — | `ProviderCapabilities.swift` (new), `LLMProvider.swift`, `ProviderProfile.swift`, `LLMProviderFactory.swift`, all adapters (add `capabilities`), `ProviderProfileEditView.swift` |
| 2. Two-lane `ToolLoopRunner` + real JSON Schema | **Claude** | 1 | `ToolLoopRunner.swift`, `ToolLoopSchema.swift`, `OpenAICompatibleProvider.swift`, coordinators (call-shape only if needed) |
| 3. OpenRouter adapter + model picker | **Codex** | 1 (merged) | `OpenRouterProvider.swift` (new) or reuse `OpenAICompatibleProvider`, `AdapterKind`, `LLMProviderFactory.swift`, `ProviderProfileEditView.swift`, model-list fetch + picker |
| 4. `ResilientProvider` decorator | **Claude** | 1, 2 | `ResilientProvider.swift` (new), `LLMProviderFactory.swift`, coordinator `recordCalls` signatures |
| 5. Apple native guided generation | **Codex** | 1 (merged) | `FoundationModelsProvider.swift`, its tests |
| 6. Streaming seam (stub) | **Claude** | 1 | `LLMProvider.swift` (extension + default), `ResilientProvider.swift`, `LLMProviderFactory.swift` |
| 7. Bedrock SigV4 colon fix | **Codex** | — | `AWSSigV4Signer.swift`, `AWSSigV4SignerTests.swift` |

**Integration order:** 1 merges first (hard dependency for 2/3/4/5). Then 2, 3,
5, 7 proceed in parallel. 4 lands after 2. 6 lands any time after 1 (bundle
with 4 if convenient). Each unit is its own PR-sized commit set with its own
review.

---

## Unit 1 — Capability layer + factory defaults  *(Claude)*

**Files:**
- Create: `FitnessCore/Sources/LLMKit/ProviderCapabilities.swift`
- Modify: `FitnessCore/Sources/LLMKit/LLMProvider.swift` (add `var capabilities`)
- Modify: `FitnessTracker/FitnessTracker/Models/ProviderProfile.swift` (override columns + `fallbackProfileID`)
- Modify: `FitnessTracker/FitnessTracker/AI/Adapters/*Provider.swift` (each returns a `static let defaultCapabilities` and `var capabilities`)
- Modify: `FitnessTracker/FitnessTracker/AI/LLMProviderFactory.swift` (default table + profile-override merge; back-fill nil overrides)
- Modify: `FitnessTracker/FitnessTracker/Features/Settings/ProviderProfileEditView.swift` (optional advanced disclosure to override caps; read-only display of the resolved value is enough for v1)
- Test: `FitnessCore/Tests/LLMKitTests/ProviderCapabilitiesTests.swift`, `FitnessTracker/FitnessTrackerTests/LLMProviderFactoryCapabilitiesTests.swift`

**Interfaces produced:** the `ProviderCapabilities` struct, `LLMProvider.capabilities`,
`ProviderProfile` cap columns, `LLMProviderFactory.resolvedCapabilities(for: ProviderProfile) -> ProviderCapabilities`.

**Steps:**
1. Write `ProviderCapabilities` exactly as in the Shared Contract. Test: round-trips `Codable`; enums decode from raw strings.
2. Add `var capabilities: ProviderCapabilities { get }` to `LLMProvider`. Give each existing adapter a `static let defaultCapabilities` per the table and `var capabilities { Self.defaultCapabilities }`. The generic `OpenAICompatibleProvider` default is `jsonObject`/`viaPrompt`; add a host check so `api.openai.com` returns `nativeJSONSchema`/`native`. Build.
3. Add the nullable cap columns + `fallbackProfileID` to `ProviderProfile`; nil in `init`. Additive migration.
4. `LLMProviderFactory`: add `defaultCapabilities(for adapterKind:baseURL:) -> ProviderCapabilities` (the table) and `resolvedCapabilities(for profile:)` that overlays non-nil profile columns. Where the factory builds a provider, pass the resolved caps into the adapter (constructor param `capabilities: ProviderCapabilities = Self.defaultCapabilities` on each adapter, factory passes the resolved value).
5. `ProviderProfileEditView`: show the resolved capabilities as a read-only `LabeledContent` group ("Structured output: JSON object", "Tools: prompt", "Streaming: yes"). An editable override picker is a nice-to-have; ship read-only if time-boxed.
6. Tests: factory returns the table default for a fresh profile of each kind; a profile with `capToolCallingRaw = "native"` overrides to `.native`; `api.openai.com` base URL flips the generic adapter to `nativeJSONSchema`.

**Done when:** every `LLMProvider` reports `capabilities`; the factory resolves
profile→default correctly; `isStrictJSONSchema` in `OpenAICompatibleProvider`
is NOT removed yet (Unit 2 does that) but its result is now cross-checked
against `capabilities.structuredOutput` — if they disagree, prefer
`capabilities` and log once. Both test targets green.

---

## Unit 2 — Two-lane `ToolLoopRunner` + real JSON Schema  *(Claude)*

**Files:**
- Modify: `FitnessTracker/FitnessTracker/AI/ToolLoopRunner.swift`
- Modify: `FitnessCore/Sources/LLMKit/ToolLoopSchema.swift`
- Modify: `FitnessTracker/FitnessTracker/AI/Adapters/OpenAICompatibleProvider.swift` (native tools request/response; drop the `isStrictJSONSchema` sniff, use `capabilities`)
- Modify: coordinators only if the `ToolLoopResult` shape changes (it should not)
- Test: `FitnessTracker/FitnessTrackerTests/ToolLoopRunnerTests.swift`, `FitnessCore/Tests/LLMKitTests/ToolLoopSchemaTests.swift`

**Interfaces consumed:** `provider.capabilities` (Unit 1).
**Interfaces produced:** unchanged `ToolLoopResult<Final>` / `ToolLoopError`. New
internal `ToolLoopRunner` lane selection.

**Steps:**
1. `ToolLoopSchema.schema(finalSchema:tools:)` currently emits a descriptive
   blob. Add `ToolLoopSchema.strictSchema(finalSchema:tools:) -> JSONSchema`
   that emits a real JSON Schema:
   `{"type":"object","additionalProperties":false,"properties":{"decision":{"enum":["tool_call","final"]},"toolCall":{…},"final":<finalSchema>},"required":["decision"]}`.
   Keep the descriptive one for `promptOnly`/`jsonObject`. Test: strict schema
   parses as valid JSON Schema; `isStrictJSONSchema` (from `cf80e49`) returns
   true for it.
2. `ToolLoopRunner.run` picks a lane from `provider.capabilities.toolCalling`:
   - **`.viaPrompt`** — today's loop unchanged (prompt concatenation, envelope
     decode, `ToolLoopTurn` implicit-final tolerance stays).
   - **`.native`** — call a new `provider.completeToolTurn(system:messages:tools:finalSchema:)`
     that returns `enum NativeTurn { case toolCalls([ToolCallRequest]); case final(Data) }`.
     Runner maintains a real `[Message]` array (system, user, assistant
     tool_calls, tool results), executes tools via the existing `ToolRegistry`,
     appends `tool` role messages, loops to `maxIterations`, decodes the final
     `Data` as `Final`. One `CallOutcome` per underlying HTTP call, same as now.
3. Add `completeToolTurn` to `LLMProvider` as an **extension with a default**
   that throws `LLMError.unsupported("native tools")` — only
   `OpenAICompatibleProvider` (and later Gemini/Bedrock/Anthropic) override it.
   `ToolLoopRunner` only takes the native lane when `capabilities.toolCalling
   == .native`, so the default is never hit in practice.
4. `OpenAICompatibleProvider`: implement `completeToolTurn` using OpenAI
   `tools` + `tool_choice: "auto"` + `response_format` from `capabilities`
   (`json_schema` strict when `.nativeJSONSchema`, else `json_object`). Remove
   the `isStrictJSONSchema` runtime sniff — the mode now comes from
   `capabilities.structuredOutput`. Keep `redactSecrets` on error bodies.
5. Tests: a stub provider with `capabilities.toolCalling == .native` drives the
   native lane (asserts messages array grows with `tool` role entries, final
   decodes); a `.viaPrompt` stub drives the old lane unchanged; billing count
   matches HTTP call count in both; `exceededMaxIterations` / `providerFailed`
   / `providerFailedWithMessage` all still carry `calls`.

**Done when:** frontier providers run native tools; cheap-tier runs the prompt
loop; every coordinator's behavior and billing is unchanged from the outside;
`isStrictJSONSchema` sniff deleted. Both targets green + the benchmark's "tool
behavior" fixtures.

---

## Unit 3 — OpenRouter adapter + model picker  *(Codex)*

**Files:**
- Create: `FitnessTracker/FitnessTracker/AI/Adapters/OpenRouterProvider.swift`
  (thin subclass/wrapper of `OpenAICompatibleProvider` with
  `baseURL = https://openrouter.ai/api/v1`, an `HTTP-Referer` + `X-Title`
  header, and `defaultCapabilities = jsonObject/viaPrompt/streaming:true`)
- Modify: `FitnessTracker/FitnessTracker/Models/AdapterKind` (or wherever it
  lives) — add `case openRouter`
- Modify: `FitnessTracker/FitnessTracker/AI/LLMProviderFactory.swift` — route
  `.openRouter` to the new provider; add its row to the default cap table
- Modify: `FitnessTracker/FitnessTracker/Features/Settings/ProviderProfileEditView.swift`
  — when `kind == .openRouter`, replace the free-text Model ID field with a
  searchable picker backed by `GET https://openrouter.ai/api/v1/models`
  (cache the list; fall back to free text if the fetch fails or offline)
- Test: `FitnessTracker/FitnessTrackerTests/OpenRouterProviderTests.swift`

**Interfaces consumed:** `ProviderCapabilities`, `LLMProvider.capabilities`
(Unit 1 — must be merged first).

**Steps:**
1. `OpenRouterProvider`: reuse `OpenAICompatibleProvider`'s request/response
   path. Only differences: fixed base URL, the two OpenRouter headers, and
   `capabilities`. If subclassing is awkward under `struct`, compose: hold an
   inner `OpenAICompatibleProvider` and forward.
2. `AdapterKind.openRouter` + factory routing + `ProviderProfileEditView`
   picker for base URL (hidden — it's fixed) and API key (shown).
3. Model picker: fetch the models list, show id + name + context length + a
   rough price; store the chosen `id` as `modelID`. Offline / fetch-fail →
   plain `TextField`, no crash. Do NOT block the sheet on the network call.
4. Tests (stubbed URLProtocol): request goes to `openrouter.ai/api/v1/chat/completions`
   with the OpenRouter headers and the bearer key; `response_format` is
   `json_object` (matches its capability); a 400 body becomes
   `LLMError.transport` and is redacted; the models-list parser handles the
   real OpenRouter JSON shape and an empty/`{"data":[]}` response.

**Done when:** a user can add an OpenRouter profile, pick a model, and Ask
Coach / plan-gen work through it end to end (verify live against one free
OpenRouter model in the simulator, screenshot in the report). Tests green.
Note in the report which models you verified.

---

## Unit 4 — `ResilientProvider` decorator  *(Claude)*

**Files:**
- Create: `FitnessTracker/FitnessTracker/AI/ResilientProvider.swift`
- Modify: `FitnessTracker/FitnessTracker/AI/LLMProviderFactory.swift` (wrap the
  resolved provider in `ResilientProvider` when the profile has a
  `fallbackProfileID` or retry is enabled)
- Modify: coordinator `recordCalls(...)` signatures to accept an
  `isFallback: Bool` (default false) so fallback attempts stamp
  `AICallRecord.usedFallback`
- Test: `FitnessTracker/FitnessTrackerTests/ResilientProviderTests.swift`

**Interfaces consumed:** `LLMProvider`, `ProviderCapabilities`,
`ProviderProfile.fallbackProfileID`, Unit 2's `completeToolTurn`.

**Steps:**
1. `struct ResilientProvider: LLMProvider` wrapping `primary: any LLMProvider`
   + `fallback: (any LLMProvider)?` + a small `RetryPolicy`
   (maxRetries, base delay, which errors retry: `.transport` on 5xx/429/timeout
   only — NOT decode errors, NOT `exceededMaxIterations`). `capabilities` =
   `primary.capabilities` (fallback may differ — expose `primary`'s; the
   runner already picked its lane before the decorator matters, so document
   that fallback must have ≥ primary's tool capability or the loop degrades).
2. `complete` / `completeWithImage` / `completeToolTurn`: try primary with
   retry; on exhausting retries, try fallback once (no retry on fallback).
   Propagate `CancellationError` immediately, no retry.
3. Billing: `ResilientProvider` does not record. It surfaces enough for the
   caller to record per attempt — simplest: it does not swallow attempts, each
   underlying `complete` that hit the network already produced its
   `LLMResult`/threw, and the coordinator's existing per-`CallOutcome` loop
   records them. The one addition: when the fallback path is taken, the
   decorator tags the returned `LLMResult`/thrown error so the coordinator
   calls `recordCalls(..., isFallback: true)`. Add a `usedFallback` bool to
   `LLMResult` (default false) OR a `ToolLoopError` associated value — pick the
   `LLMResult` field, it's cleaner.
4. Tests: primary 500 → retry → success (2 `AICallRecord`, first `success:false`,
   second `success:true`, both `usedFallback:false`); primary exhausts retries
   → fallback success (records show `usedFallback:true` on the fallback one);
   `CancellationError` on primary → thrown immediately, no fallback, no retry;
   decode error on primary → NOT retried, straight to fallback or throw;
   fallback also fails → original primary error surfaces (not the fallback's).

**Done when:** a profile with a `fallbackProfileID` transparently fails over;
every attempt bills exactly once; `usedFallback` is accurate; cancellation is
instant. Benchmark's "failed calls billed exactly once / fallback attempts
preserve usage records" fixtures pass.

---

## Unit 5 — Apple native guided generation  *(Codex)*

**Files:**
- Modify: `FitnessTracker/FitnessTracker/AI/Adapters/FoundationModelsProvider.swift`
- Test: `FitnessTracker/FitnessTrackerTests/FoundationModelsProviderTests.swift`

**Interfaces consumed:** `ProviderCapabilities` (Unit 1 — merged first).

**Context:** today this adapter embeds a JSON schema string in the prompt and
decodes the returned text. The iPhoneOS 26.5 SDK exposes `Generable`,
`DynamicGenerationSchema`, and guided `respond(schema:)`. No `Attachment`
symbol → keep `completeWithImage` reporting `visionUnsupported`.

**Steps:**
1. Replace prompt-embedded schema with `DynamicGenerationSchema` built from the
   incoming `JSONSchema.json` (parse the descriptive shape → dynamic schema
   fields; the app's schemas are shallow objects of string/number/array).
   Where the schema is the tool-loop envelope, build the dynamic schema for
   that.
2. Use `session.respond(to:schema:)` (guided) and decode the structured result
   into `Value` via `JSONDecoder` on its JSON representation. Preserve
   `LLMResult` usage fields (token counts if FM exposes them; 0 if not).
3. `defaultCapabilities`: `structuredOutput: .nativeJSONSchema`,
   `toolCalling: .viaPrompt` (native `Tool` API is out of scope for this unit —
   note it as a follow-up), `streaming: false`, `vision: false`.
4. Availability: if Foundation Models is unavailable on the device/simulator,
   `complete` throws a clear `LLMError` (existing behavior) — the resilience
   layer (Unit 4) will fail over from it.
5. Tests: guided decode of a representative plan/summary schema (mock the FM
   session if the test env can't run it — the SDK's `SystemLanguageModel`
   availability check gates this; skip with a recorded reason on the simulator
   if assets are absent, exactly as the prior session documented).

**Done when:** the Apple adapter uses guided generation, not prompt embedding;
`capabilities` reports `nativeJSONSchema`; unavailable-device path still throws
cleanly. Report whether it was validated on a real device or skipped.

---

## Unit 6 — Streaming seam (stub)  *(Claude)*

**Files:**
- Modify: `FitnessCore/Sources/LLMKit/LLMProvider.swift`
- Modify: `FitnessTracker/FitnessTracker/AI/ResilientProvider.swift` (passthrough)
- Test: `FitnessCore/Tests/LLMKitTests/LLMProviderStreamingDefaultTests.swift`

**Steps:**
1. Add, as a protocol **extension with a default** (not a new requirement):
   ```swift
   extension LLMProvider {
       func stream(system: String, user: String) -> AsyncThrowingStream<String, Error> {
           AsyncThrowingStream { c in
               Task {
                   do { let r: LLMResult<StringBox> = try await complete(system:system,user:user,schema:.plainText,as:StringBox.self)
                        c.yield(r.value.text); c.finish() }
                   catch { c.finish(throwing: error) }
               }
           }
       }
   }
   ```
   (or the minimal shape that fits `LLMResult`). No provider implements real
   token streaming yet.
2. `ResilientProvider` forwards `stream` to primary (no retry/fallback on
   streams for v1 — document it).
3. Test: default `stream` yields the whole completion once then finishes;
   errors propagate.

**Done when:** the seam exists, defaults work, nothing calls it yet. This unit
is deliberately tiny — it only prevents a future paint-in.

---

## Unit 7 — Bedrock SigV4 colon fix  *(Codex)*

**Files:**
- Modify: `FitnessTracker/FitnessTracker/AI/Adapters/AWSSigV4Signer.swift`
- Test: `FitnessTracker/FitnessTrackerTests/AWSSigV4SignerTests.swift`

**Bug:** `canonicalURI = request.url?.path` — `URL.path` leaves `:` literal;
AWS canonicalises path segments with `%3A`, so a Bedrock model id like
`us.anthropic.claude-3-5-sonnet-20241022-v2:0` in the path → `403
SignatureDoesNotMatch`.

**Steps:**
1. Build the canonical URI by percent-encoding each `/`-split path segment with
   an RFC-3986 unreserved set (`A-Za-z0-9-._~`) — NOT `.urlPathAllowed` (which
   permits `:`). Rejoin with `/`. Empty path → `/`.
2. Test: a request to `.../model/us.anthropic.claude-3-5-sonnet-20241022-v2:0/invoke`
   produces a canonical URI containing `%3A0` and NOT a literal `:`; an
   already-safe path is unchanged; root path stays `/`. If there's an existing
   known-good signature fixture, add one with a colon'd model id.

**Done when:** colon'd Bedrock model ids sign correctly; existing SigV4 tests
still pass.

---

## Review process (per unit)

Each unit: implement → self-test both targets → commit (one focused commit or
a small series) → the other party (or a reviewer) reads the diff against this
plan's "Done when". Claude's units get a task-review pass; Codex's units come
back to Claude for a read against the shared contract before they're
considered landed. After all seven, one whole-branch review on the most
capable model, one consolidated fix wave, then merge `ai-harness-v2` → `main`.

## Known preexisting issues — DO NOT fix here
- `ProactiveCoordinatorTests` first-pass flake (shared `UserDefaults.standard`
  / notification-center state; passes on retry). Separate cleanup.
- `SessionFinalizeCoordinator` calls `FinalizeGuardrail.check` with hardcoded
  context (`lastPerformances: [:]`, empty exclusions, all equipment) — the
  load-jump safety cap is inert. Tracked in
  `docs/2026-09-06-external-audit-review.md`. Adjacent to this work but its own
  task.
