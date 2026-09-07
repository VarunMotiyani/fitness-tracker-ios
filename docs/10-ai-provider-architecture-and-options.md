# AI Provider Architecture and Options

**Captured:** 2026-09-07  
**Scope:** Fitness Tracker AI module and the possible standalone Swift AI runtime/router idea  
**Status:** Architecture research; no implementation decision beyond the current `LLMProvider` boundary

## Executive summary

The app already has a sensible provider seam: a small, domain-owned `LLMProvider` protocol in `FitnessCore`, app-target adapters, and a separate tool-loop/orchestration layer. The app does not need a hosted backend to execute AI logic; it can act as an in-process orchestrator and call cloud or local providers directly.

Several Swift packages now cover parts of the problem. The category is not empty, but there is still no clearly mature, single package that combines LiteLLM-style routing, Apple Foundation Models, local inference, provider capability negotiation, reliable tool/schema translation, and production-grade conformance tests.

The safest direction for Fitness Tracker is therefore incremental:

1. Keep `LLMProvider` as the stable app contract.
2. Use existing packages behind adapters where they remove real complexity.
3. Do not replace the domain contract or `ToolLoopRunner` until a package passes the app’s provider, schema, tool, billing, and failure tests.
4. If a new standalone project is pursued, position it as a reliability-first Swift runtime/router rather than “the first LiteLLM for Swift.”

## Current app architecture

### Provider boundary

[`FitnessCore/Sources/LLMKit/LLMProvider.swift`](../FitnessCore/Sources/LLMKit/LLMProvider.swift) exposes two operations:

- `complete(system:user:schema:as:)` for typed structured responses
- `completeWithImage(...)` for future vision-capable providers

The protocol is `Sendable`, provider-neutral, and intentionally does not know about networking, API keys, SwiftUI, or the fitness domain.

### Current adapters and factory

The app target owns concrete provider implementations and `LLMProviderFactory`:

- OpenAI-compatible HTTP adapter (including Groq/Qwen and similar endpoints)
- Gemini adapter
- Apple Foundation Models adapter
- Vertex AI and Bedrock factory paths
- Runtime `ProviderProfile` configuration and Keychain lookup

The factory resolves a profile into an `any LLMProvider`, keeping the rest of the app independent of the provider choice.

### Tool and domain orchestration

[`FitnessTracker/FitnessTracker/AI/ToolLoopRunner.swift`](../FitnessTracker/FitnessTracker/AI/ToolLoopRunner.swift) runs a manual, provider-neutral tool protocol:

1. Send a typed `ToolLoopTurn` schema.
2. Decode either a tool call or a final DTO.
3. Execute the registered tool deterministically in the app.
4. Append the tool result to the next prompt.
5. Stop at a bounded iteration count.

This is deliberately separate from provider-native function calling. It gives the app the same behavior across providers whose native tool APIs differ or are unreliable.

### Validation and accounting

AI outputs are decoded into typed DTOs, validated against the exercise catalog and rule engine, and recorded for usage/cost accounting. These are app responsibilities and should not be delegated blindly to a generic SDK.

## Problems encountered

### Groq/Qwen JSON failure

The Groq-compatible endpoint was reachable, but Qwen returned HTTP 400 with a “failed to generate JSON” error. The request sent a descriptive app schema as strict OpenAI `json_schema`; Groq requires a stricter JSON Schema shape for that mode.

The adapter was changed to choose between:

- strict `json_schema` only for schemas that are actually strict-compatible;
- JSON Object Mode plus an explicit JSON-only instruction for descriptive schemas.

Qwen then returned a direct final DTO rather than the expected `ToolLoopTurn` envelope. The decoder was updated to treat a valid direct DTO as an implicit final turn. This is an important lesson: “OpenAI-compatible” describes a wire family, not identical structured-output or tool semantics.

### Apple adapter limitations

The current Apple adapter manually embeds a JSON schema in the prompt and decodes the returned text. It does not yet use Foundation Models’ native guided generation or native `Tool` API. `completeWithImage` currently reports vision unsupported.

The local iPhoneOS 26.5 SDK exposes `Generable`, `DynamicGenerationSchema`, guided `respond(schema:)`, and native tools, but no `Attachment` symbol was found in the SDK currently used by this project. Image support therefore cannot be assumed from newer documentation alone.

### Model ID confusion

The model ID is the provider’s routing identifier, not an arbitrary name. For example, `qwen/qwen3.8-27b` is interpreted by Groq, while an Apple on-device provider may not need a user-selected model ID at all. A generic provider profile needs to distinguish:

- a user-facing alias, such as `smart` or `local`;
- the adapter/provider kind;
- the provider’s exact model ID;
- the endpoint/base URL;
- capability metadata.

### Direct app calls versus a backend

The app can contain orchestration logic, tool execution, retries, validation, persistence, and routing. In that sense it is the application’s AI runtime. It cannot safely provide the organization-wide functions of a hosted gateway when cloud secrets are shipped to clients.

LiteLLM’s gateway features include virtual keys, budgets, centralized spend tracking, admin UI, guardrails, and organization-wide observability. Those are server-side concerns by nature. ([LiteLLM documentation](https://docs.litellm.ai/docs/))

Direct app calls remain valid for a user-managed-key app, local models, Apple Foundation Models, prototypes, and privacy-sensitive offline flows. A production consumer app should not treat an embedded provider key as a secret.

## Requirements for the AI layer

The practical requirements discussed so far are:

- no required hosted backend;
- Apple Foundation Models as an on-device/private fallback;
- Groq/Qwen and arbitrary OpenAI-compatible endpoints;
- typed structured output for workout plans and summaries;
- multi-step tool calls for plan edits, memory, and proactive actions;
- streaming where the provider supports it;
- optional image/vision input;
- retries, fallback, cancellation, and bounded loops;
- normalized provider errors and usage metadata;
- provider/model selection from settings without app-code rewrites;
- compatibility with the existing validation and billing pipeline;
- small SwiftPM dependency surface and no unnecessary local inference payloads.

## What LiteLLM provides—and what it does not

LiteLLM is both a Python SDK and a self-hosted AI gateway. Its core value is a unified OpenAI-shaped interface across 100+ providers, normalized outputs/errors, retries/fallbacks, routing, usage/cost tracking, and proxy features. ([LiteLLM getting started](https://docs.litellm.ai/docs/))

An in-process Swift package can reproduce the SDK-side parts:

- provider adapters;
- normalized requests/responses/events;
- aliases and routing;
- retries and fallbacks;
- structured output and tools;
- local/on-device backends.

It cannot reproduce the gateway-side parts without a service:

- protecting one central set of provider credentials;
- virtual keys and tenant budgets;
- centralized logs and spend accounting;
- admin controls and organization policy;
- shared rate limits across many app installations.

The correct comparison is therefore “LiteLLM SDK concepts in Swift,” not “the entire LiteLLM gateway inside an iOS app.”

## Existing Swift ecosystem

The following projects were reviewed as of 2026-09-07. Their feature lists and test counts are project-reported; semver, activity, issue counts, and roadmap status are useful maturity signals but are not guarantees of production quality.

### `teunlao/swift-ai-sdk`

[Repository](https://github.com/teunlao/swift-ai-sdk)

Broad Vercel AI SDK-style framework with 38 provider modules, streaming, typed `Codable`/JSON Schema output, tools, MCP, middleware, and provider swapping. Its `0.19.0` release reports 4,158 tests across 473 suites.

**Good for:** a broad AI SDK surface and provider coverage.  
**Caveat:** the primary README does not make Apple Foundation Models the center of its design, and adopting it would be a larger abstraction migration than wrapping one adapter.

### `zaidmukaddam/swift-ai-sdk`

[Repository](https://github.com/zaidmukaddam/swift-ai-sdk)

Targets iOS/macOS directly and presents the same API for cloud and on-device models. It includes Foundation Models, OpenAI-compatible providers, Groq, structured output, a multi-step tool loop, `ChatSession`, MCP, realtime sessions, provider registry, and simulator-tested example apps. It reports 376 tests. Its roadmap still lists an `@Generable`-style macro and an MLX provider.

**Good for:** a larger future migration away from the hand-built tool/streaming layer.  
**Caveat:** broad surface area, pre-1.0-style churn, and not a drop-in match for our `LLMProvider`/billing contract.

### Hugging Face `AnyLanguageModel`

[Repository](https://github.com/huggingface/AnyLanguageModel) · [announcement](https://huggingface.co/blog/anylanguagemodel)

Provides a drop-in Foundation Models-shaped API for Apple, Core ML, MLX, llama.cpp, Ollama, OpenAI, Anthropic, Gemini, and Hugging Face providers. It uses Swift package traits to avoid pulling heavy local backends into every app. The current release line is pre-1.0; its own announcement lists tool calling across all providers, MCP, guided generation, and local performance work as ongoing.

**Good for:** replacing or simplifying the Apple/local adapter while preserving Apple’s session/tool/generation mental model.  
**Caveat:** not yet a complete cross-provider production contract.

### `christopherkarani/Conduit`

[Repository](https://github.com/christopherkarani/Conduit)

Provides typed local/cloud inference, compile-time schemas with `@Generable`, native tools, streaming, SwiftUI support, MLX, Core ML, llama.cpp, Ollama, OpenAI, Anthropic, Gemini, and other provider traits. Current release reviewed: `0.3.17`.

**Good for:** local Apple Silicon inference and strongly typed Swift-first APIs.  
**Caveat:** pre-1.0; its schema/macro model would require a deliberate change to our current `JSONSchema` contract.

### `intelc/swift-litellm`

[Repository](https://github.com/intelc/swift-litellm)

The closest literal match to the LiteLLM idea: aliases, retries, fallbacks, normalized streaming, OpenAI-compatible endpoints, Anthropic, Gemini, Ollama, MLX bridges, custom in-process providers, and an Apple Foundation Models route. It explicitly says it is a lightweight router, not a gateway or full agent framework. Its provider matrix labels the implementations early, and the repository currently has very little commit history.

**Good for:** a small routing layer behind our existing provider contract.  
**Caveat:** too early to trust as the sole provider/runtime layer, and it does not replace our Vertex/Bedrock paths.

### `ManifoldKit`

[Repository](https://github.com/ManifoldKit/ManifoldKit)

An opinionated full-stack SwiftUI chat product combining UI, turn-loop runtime, persistence, MCP, RAG, tools, model management, and multiple backends.

**Good for:** shipping a complete chat product with its conventions.  
**Caveat:** it overlaps with Fitness Tracker’s UI, persistence, coordinators, and domain orchestration, so it is not a good neutral `LLMProvider` dependency.

### Other narrower projects

- [LocalLLMClient](https://github.com/tattn/LocalLLMClient): local MLX/GGUF/Foundation Models with streaming and experimental multimodal/tool support; explicitly experimental.
- [LLMProviderKit](https://github.com/ayman3000/LLMProviderKit): a small native-provider protocol for Ollama, OpenAI-compatible endpoints, Gemini, and Anthropic, with streaming/tools/vision; useful as a reference but narrower than our required surface.
- [Dean151/swift-ai](https://github.com/Dean151/swift-ai): historically broad, but the repository is archived and states that it is no longer maintained.
- [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk): official Swift MCP client/server protocol support; it standardizes tool transport, not model-provider routing.

## Options for Fitness Tracker

### Option 1: Keep the current implementation

**Shape:** retain `LLMProvider`, the current adapters, and `ToolLoopRunner`; improve each provider deliberately.

**Pros**

- Smallest risk and no new dependency churn.
- Preserves the current typed DTO, validation, billing, and error semantics.
- Lets us fix Qwen/Groq behavior exactly where it occurs.
- Keeps native Vertex and Bedrock paths available.
- Keeps the manual tool loop deterministic across providers.

**Cons**

- We continue owning provider wire formats, streaming, and schema edge cases.
- Apple guided generation/tool support requires more work.
- No common routing/alias layer yet.

**Best use:** current production path while we gather compatibility evidence.

### Option 2: Package-backed adapters

**Shape:** keep `LLMProvider`, but implement one or more adapters using an external package.

Likely assignments:

- `AnyLanguageModel` behind `FoundationModelsProvider` and optional local adapters.
- A broad Swift AI SDK behind a future cloud adapter.
- `swift-litellm` behind a routing adapter.

**Pros**

- Preserves our domain seam.
- Allows incremental rollback if a package breaks or changes API.
- Reduces repetitive wire-format code.

**Cons**

- We still need schema translation from our `JSONSchema` to the package’s schema type.
- We still need to map package results into `LLMResult` and our usage ledger.
- Two abstractions can drift if not tested at the boundary.

**Best use:** the recommended near-term approach.

### Option 3: Replace `LLMProvider` with a broad Swift AI SDK

**Shape:** make an SDK’s `LanguageModel`/provider protocol the app-wide AI contract and migrate coordinators/tool loops.

**Pros**

- Potentially removes our manual tool loop and adds streaming/realtime/media capabilities.
- Provider modules and structured output are maintained outside the app.
- A more standard ecosystem API may ease future integrations.

**Cons**

- High migration surface across coordinators, tests, billing, error handling, and settings.
- Provider capabilities may be normalized too aggressively for fitness-specific safety rules.
- Packages are young and APIs are moving quickly.
- Vertex, Bedrock, Apple availability, and our exact schema semantics still require verification.

**Best use:** only after a measured spike passes the full app contract.

### Option 4: Add an in-process router

**Shape:** `LLMProviderFactory` returns a routing provider with aliases such as `smart`, `fast`, and `local`; the router chooses concrete providers, retries, and falls back.

**Pros**

- Removes provider IDs from feature code.
- Enables Apple-local fallback when cloud calls fail or are unavailable.
- Centralizes retry/fallback policy and telemetry.

**Cons**

- Routing cannot make an unsupported model support tools or JSON schema.
- Fallbacks can change output quality and cost unexpectedly.
- `swift-litellm` is early, so adopting it wholesale is risky.
- Provider-specific features still need explicit capability metadata.

**Best use:** add a thin local policy layer first; optionally back it with `swift-litellm` after benchmarking.

### Option 5: Build a new standalone Swift package

**Shape:** create a reusable Swift runtime/router rather than another provider wrapper.

**Pros**

- A real gap remains around reliability and capability-aware behavior.
- Can be designed for native Apple constraints from the start.
- Could provide conformance fixtures that existing packages lack.

**Cons**

- The basic category is already crowded.
- Provider maintenance is expensive and continuous.
- Apple’s own provider direction may commoditize basic model access.

**Best use:** build only after benchmarking existing packages and identifying repeated failures.

## Recommended architecture

Keep the app-owned domain contract and add policy layers around it:

```text
Feature coordinators
        |
        v
ToolLoopRunner / DTO validation / billing
        |
        v
LLMProvider  (stable FitnessCore contract)
        |
        +--> ResilientProvider / alias router (optional)
        |          |
        |          +--> Apple Foundation Models adapter
        |          +--> OpenAI-compatible adapter (Groq/Qwen)
        |          +--> Gemini / Vertex adapter
        |          +--> Bedrock adapter
        |          +--> local MLX/llama.cpp adapter (optional)
        |
        +--> package-backed implementations where proven
```

The key boundary is that packages remain replaceable implementation details. Fitness-specific validation, tool authorization, persistence, and cost records stay in the app.

## Where each existing package could help

| App concern | Candidate | Why | Adoption posture |
|---|---|---|---|
| Apple structured output/tools | AnyLanguageModel | Apple-shaped API and native/local backends | Spike behind `FoundationModelsProvider` |
| Cloud + Apple unified API | zaidmukaddam Swift AI SDK | Broad iOS-oriented API, tools, agents, streaming, Foundation Models | Evaluate in a separate adapter target |
| Provider breadth and middleware | teunlao Swift AI SDK | Broad provider modules and Vercel parity | Consider only for a larger migration |
| Aliases/fallbacks/retries | swift-litellm | Directly models the router problem | Use only behind our contract until mature |
| MLX/Core ML/GGUF | Conduit or AnyLanguageModel | Native local inference support | Optional; not needed for Apple system model alone |
| UI/chat persistence | None initially | ManifoldKit overlaps our app architecture | Do not adopt for the provider layer |

## Compatibility benchmark before changing the contract

Every candidate should be tested against the same fixture suite:

### Request and response behavior

- plain text completion;
- strict JSON Schema;
- descriptive/non-strict schema fallback;
- direct DTO response without a tool envelope;
- malformed JSON and fenced JSON;
- empty content and provider error bodies;
- usage/token metadata when available.

### Tool behavior

- one tool call;
- multiple sequential calls;
- invalid tool name;
- malformed tool arguments;
- tool failure and retry;
- max-iteration termination;
- user approval or denial for mutating tools;
- cancellation during a provider call and during tool execution.

### Provider matrix

- Apple Foundation Models available;
- Apple Foundation Models unavailable;
- Groq/Qwen OpenAI-compatible endpoint;
- another OpenAI-compatible endpoint with different JSON restrictions;
- Gemini;
- Vertex and Bedrock if those remain supported;
- optional Ollama/MLX/local model.

### Fitness-domain invariants

- generated exercise IDs exist in the catalog;
- plan mutations pass rule-engine validation;
- failed calls are billed exactly once;
- fallback attempts preserve call-level usage records;
- proactive and memory coordinators receive the same typed result semantics as Ask Coach.

## Security and product constraints

- Keychain storage protects keys at rest on the device but does not make a client-embedded key equivalent to a server secret.
- User-managed keys are acceptable for the current prototype/product direction; a consumer-scale release should consider a proxy or provider-specific short-lived credentials.
- Logs and error messages must redact API keys and avoid storing sensitive workout context unnecessarily.
- A router should expose policy and capability decisions for diagnostics, but not leak credentials or raw private prompts.
- Heavy local inference dependencies should be opt-in SwiftPM products/traits so users who only need Apple Foundation Models do not ship MLX or llama.cpp.

## Phased plan

### Phase A — stabilize the current contract

- Keep `LLMProvider` and `ToolLoopRunner` unchanged.
- Expand provider fixtures for Qwen/Groq schema behavior and direct DTO responses.
- Add explicit capability metadata to `ProviderProfile`.
- Define the Apple adapter’s guided-generation/tool behavior against the SDK actually used by the project.

### Phase B — package spikes, not migration

- Build a temporary `AnyLanguageModel` Apple adapter.
- Build a temporary `swift-litellm` routing adapter.
- Optionally build a `zaidmukaddam/swift-ai-sdk` adapter for one non-mutating coordinator.
- Run only the compatibility benchmark above; compare code size, compile time, errors, tests, and behavior.

### Phase C — adopt selectively

Adopt a package only when it removes meaningful code without weakening domain invariants. Keep the old adapter available until the package-backed path has passed simulator and live-provider checks.

### Phase D — standalone project decision

If multiple packages fail on the same issues—especially capability negotiation, tool reliability, Apple fallback, or conformance testing—those failures justify a separate Swift runtime/router project.

## Current recommendation

For Fitness Tracker today:

1. Do not replace `LLMProvider`.
2. Do not adopt ManifoldKit for the AI layer.
3. Treat `AnyLanguageModel` as the best Apple/local adapter experiment.
4. Treat `swift-litellm` as the best routing experiment, not yet as a trusted foundation.
5. Treat `zaidmukaddam/swift-ai-sdk` as the strongest larger-migration candidate.
6. Preserve the custom tool loop until native package tool behavior proves equivalent under the fitness-domain benchmark.
7. Keep the standalone package idea open, but differentiate on reliability, capability truthfulness, conformance testing, and Apple-native deployment—not merely provider count.

## Reference links

- [Apple Foundation Models documentation](https://developer.apple.com/documentation/FoundationModels/)
- [Apple guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation)
- [Apple multimodal prompting](https://developer.apple.com/documentation/foundationmodels/analyzing-images-with-multimodal-prompting)
- [Apple provider session, WWDC26](https://developer.apple.com/videos/play/wwdc2026/339/)
- [LiteLLM documentation](https://docs.litellm.ai/docs/)
- [teunlao/swift-ai-sdk](https://github.com/teunlao/swift-ai-sdk)
- [zaidmukaddam/swift-ai-sdk](https://github.com/zaidmukaddam/swift-ai-sdk)
- [Hugging Face AnyLanguageModel](https://github.com/huggingface/AnyLanguageModel)
- [AnyLanguageModel announcement](https://huggingface.co/blog/anylanguagemodel)
- [Conduit](https://github.com/christopherkarani/Conduit)
- [swift-litellm](https://github.com/intelc/swift-litellm)
- [ManifoldKit](https://github.com/ManifoldKit/ManifoldKit)
- [LocalLLMClient](https://github.com/tattn/LocalLLMClient)
- [LLMProviderKit](https://github.com/ayman3000/LLMProviderKit)
- [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk)
