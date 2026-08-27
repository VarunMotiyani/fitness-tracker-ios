# 03 — Technical Architecture

_Date: 2026-08-27_

Behaviour is in [02-product-design.md](02-product-design.md). This doc is the
"how it's built."

---

## 1. Stack

| Layer | Choice | Why |
|-------|--------|-----|
| UI | **SwiftUI**, iOS 26+ | Native, first-party, fastest path for an experienced engineer on their first iOS app. Min-deployment = iOS 26 because the user's only device (iPhone 14) is on iOS 26; no reason to support older. |
| Local storage | **SwiftData** | Profile, training history, InBody series, catalog, cached plans. No server needed. |
| Secrets | **Keychain** | Stores the user's model API key. |
| AI | **Direct HTTPS** to an LLM provider behind an `LLMProvider` protocol; provider/model **TBD** (research pending) | No backend, no proxy, no auth service. User pays per use on their own key. Provider + model are runtime config; any adapter (Gemini / OpenAI / Anthropic / router / local) plugs in. |
| Exercise content | **Bundled JSON + images** in the app bundle | Offline, no CDN, licensed from an open dataset. |
| Reminders | **UserNotifications** (local) | No push server. |
| Target device | iPhone only (iPhone 14 today, iPhone 17 Pro later) | Watch companion is a later phase. |

**No backend. No accounts. No analytics service. Single user.**

---

## 2. Module boundaries

Each module has one job, a defined interface, and can be tested alone.

```
┌─────────────────────────────────────────────────────────────┐
│ UI (SwiftUI views)                                           │
│  Onboarding · Plan view · Session runner · InBody · Settings │
└───────────────┬─────────────────────────────────────────────┘
                │
┌───────────────▼───────────────┐   ┌─────────────────────────┐
│ PlanCoordinator               │   │ CatalogStore            │
│  orchestrates a plan/session  │◄──┤  loads + queries the    │
│  request end to end           │   │  bundled exercise catalog│
└───┬───────────────┬───────────┘   └─────────────────────────┘
    │               │
┌───▼──────────┐ ┌──▼────────────────┐ ┌──────────────────────┐
│ RuleEngine   │ │ AIClient          │ │ Validator            │
│  templates,  │ │  builds requests, │ │  checks every AI     │
│  volume      │ │  calls LLMProvider│ │  response against    │
│  landmarks,  │ │  decodes JSON     │ │  catalog + rules     │
│  progression,│ └───────────────────┘ └──────────────────────┘
│  load caps,  │
│  swap search │ ┌───────────────────┐ ┌──────────────────────┐
└──────────────┘ │ InBodyExtractor   │ │ PersistenceStore     │
                 │  photo → fields   │ │  SwiftData wrapper    │
                 └───────────────────┘ └──────────────────────┘
                 ┌───────────────────┐
                 │ NotificationScheduler                       │
                 └────────────────────────────────────────────┘
```

- **RuleEngine** is pure logic, no I/O — the safety-critical core, most heavily
  tested.
- **AIClient** knows nothing about training; it sends a prompt + JSON schema and
  returns decoded structs. It talks to an `LLMProvider`; concrete adapters
  (Gemini / OpenAI / Anthropic / router / local) are interchangeable and the
  final choice is deferred research.
- **Validator** is the gate between AI output and the rest of the app.
- **PlanCoordinator** is the only place that composes RuleEngine + AIClient +
  Validator into a result, and owns the retry/fallback policy.

---

## 3. Data model (SwiftData)

Illustrative — field names will firm up in the implementation plan.

### UserProfile
`goalPrimary`, `goalWeights`, `experienceLevel`, `heightCm`, `sex`, `birthDate`,
`sessionsPerWeekTarget`, `sessionLengthMinutes`, `createdAt`, `updatedAt`.

### BodyWeightEntry
`date`, `weightKg`, `source` (manual / InBody).

### EquipmentItem
`type` (enum: barbell, dumbbell, cableStack, legPress, hackSquat, …),
`available` (bool), `notes` (e.g. "dumbbells to 40 kg"), `maxLoadKg?`.

### Limitation
`region` (enum: lowerBack, leftShoulder, knee, …), `severity`,
`excludedExerciseIDs` (explicit "won't do"), `note`, `active`, `createdAt`.

### Exercise  _(from bundled catalog, read-only at runtime)_
`id` (stable string), `name`, `primaryMuscle`, `secondaryMuscles[]`,
`requiredEquipment[]`, `movementPattern` (squat, hinge, horizontalPush, …),
`difficulty`, `defaultRepRange`, `instructionSteps[]`, `imageAssetNames[]`,
`isUnilateral`.

### WeeklyPlan
`weekStart`, `generatedAt`, `source` (ai / fallback), `rationale` (the one-line
"why"), `sessions: [PlannedSession]`, `muscleVolumeGoals: [MuscleGroup: Int]`.

### PlannedSession
`id`, `orderHint`, `focusMuscles[]`, `items: [PlannedItem]`, `status`
(pending / completed / partial / skipped-rolled).

### PlannedItem
`exerciseID`, `targetSets`, `targetReps`, `targetLoadKg`, `restSeconds`,
`coachNote`.

### CompletedSession
`date`, `plannedSessionID?`, `energyRating`, `timeAvailableMinutes`,
`overallNote`, `entries: [CompletedEntry]`, `totalVolumeByMuscle`.

### CompletedEntry
`exerciseID`, `wasSwappedFrom?`, `sets: [LoggedSet]`, `feedback`
(easy / right / brutal), `note`.

### LoggedSet
`reps`, `loadKg`, `timestamp`.

### InBodyScan
`date`, `imageAssetName`, `weightKg`, `pbfPercent`, `smmKg`, `bmrKcal`,
`totalBodyWaterL`, `proteinKg`, `mineralKg`, `visceralFatLevel`, `inBodyScore`,
`segmental: [SegmentLean]`, `extractionConfidence`, `userConfirmed` (bool).

### SegmentLean
`segment` (leftArm, rightArm, trunk, leftLeg, rightLeg), `leanMassKg`,
`percentOfIdeal`.

### AppSettings
`notificationPrefs`, `activeProviderProfileID`, `visionProviderProfileID?`
(fallback for InBody if the active model has no vision), `monthlyBudgetUSD?`,
`pauseAIWhenOverBudget` (bool, default false), `historyWindowWeeks`.

### ProviderProfile
User-managed (add / edit / delete / activate in Settings). Lets a new
provider or model be adopted with **no app update**.
`id`, `displayName`, `adapterKind` (enum: `openAICompatible` / `gemini` /
`anthropic` / `appleOnDevice`), `baseURL?` (for `openAICompatible`),
`apiKeyRef` (Keychain), `modelID` (free text), `supportsVision` (bool),
`pricePerMTokIn`, `pricePerMTokOut`, `pricePerMTokCached`, `createdAt`.
- The four `adapterKind`s are the only code paths that ship. Because almost every
  new vendor (OpenRouter, Groq, DeepSeek, xAI, new OpenAI/Gemini/Anthropic
  models…) exposes an OpenAI-compatible endpoint, "add a provider" = new profile
  with `openAICompatible` + base URL + model ID + key + prices. "New model, same
  provider" = edit `modelID`.
- Ships with one seeded profile for the provisional Phase-1 model.

### AICallRecord
One row per LLM call — the real-time cost ledger.
`timestamp`, `callType` (enum: `weeklyPlan` / `adjust` / `finalize` / `swap` /
`feedback` / `inbody`), `providerDisplayName`, `modelID`, `inputTokens`,
`outputTokens`, `cachedTokens`, `costUSD` (computed at write time from the
profile's price fields), `success` (bool), `usedFallback` (bool).
- Aggregations (month-to-date, all-time, per-`callType`, 30-day series) are
  computed from this table, not stored as counters.

---

## 4. Exercise catalog

- **Base dataset: `yuhonas/free-exercise-db`** — ~873 exercises, **Unlicense
  (public domain, no attribution)**, so it can be bundled with zero legal risk.
  Fields: `id, name, force, level, mechanic, equipment, primaryMuscles,
  secondaryMuscles, instructions, category, images[]`. Media is **static JPGs**
  (typically a start-position and end-position frame per exercise) — not
  animated.
- **Why not the GIF datasets:** the comprehensive animated sets (ExerciseDB API,
  `hasaneyldrm/exercises-dataset`, MuscleWiki) all use **GymVisual-licensed or
  otherwise commercial media** — not redistributable without a paid license.
  Deferred as a possible later upgrade (see below).
- **Gap-fill (optional):** `wger` exercise data is **CC-BY-SA** (attribution +
  share-alike) — usable for entries free-exercise-db lacks, with an attribution
  file. Only if needed.
- **v1: a curated ~100–150-exercise subset** of the base dataset covering every
  major movement pattern across barbell / dumbbell / machine / cable /
  bodyweight, mapped to the app's own `Exercise` schema (see §3).
- Shipped as `catalog.json` + an image asset folder in the app bundle. Actual
  license text of the source(s) committed to the repo.
- `CatalogStore` loads it once, indexes by `id`, `primaryMuscle`,
  `requiredEquipment`, `movementPattern`.
- **Media layer is swappable.** The `Exercise` schema separates media refs
  (`imageAssetNames[]`) from exercise data, so a future paid GymVisual/animated
  media licence can replace the images without touching planning, validation, or
  the rest of the catalog.
- **Hard rule:** the AI may only prescribe `exerciseID`s that exist in the
  catalog. Anything else is rejected by the Validator.

---

## 5. Rule engine

Pure functions. No network, no storage.

- **Split templates** — full body, upper/lower, PPL, Arnold. Each defines session
  count, per-session focus muscles, and set/rep scheme bands. The engine picks a
  template from experience + weekly capacity + goal.
- **Volume landmarks** — a hardcoded table of **weekly working-set counts per
  muscle group per experience level** (a minimum below which growth stalls, a
  productive target range, and a ceiling above which it's junk volume / poor
  recovery). Values seeded from a published strength-training reference
  (Renaissance Periodization-style MEV/MAV/MRV landmarks) and tuned later from
  real logs — the exact numbers are a config table, not logic. Every AI plan and
  adaptation is clamped into this band: it's what stops the model prescribing 2
  sets or 35 sets for a muscle group.
- **Progression rule** — given last logged performance vs. target and the
  feedback rating: `easy` + hit reps → +load (capped); `right` → repeat or small
  bump; `brutal` / missed reps → hold or −load. Per-session load-increase cap
  enforced here.
- **Swap search** — given an exercise + available equipment + a "presumed busy"
  flag on the original's equipment: return ranked candidates with the same
  `primaryMuscle`, compatible `defaultRepRange`, equipment owned, not excluded by
  a Limitation. Used both for the in-session Swap button and as a deterministic
  fallback if the AI swap call fails.
- **Rest-gap check** — rejects a plan that puts two heavy sessions for the same
  muscle group without an adequate gap given how the user actually trains.

---

## 6. AI contract

Every call is **structured request → structured JSON response**. The app decodes
into Swift structs; it never parses loose prose.

### 6.1 Weekly plan generation
**Sent:** profile, equipment list, active limitations + niggle list, last 4–6
weeks of `CompletedSession` summaries, latest `InBodyScan`, the chosen template,
the volume-landmark band, the catalog slice for owned equipment (ids + names +
muscles + rep ranges).
**Returned:** `WeeklyPlan` — sessions, each with `PlannedItem`s referencing
catalog ids only, plus `targetSets/Reps/LoadKg`, `restSeconds`, `coachNote`, and
a top-level one-line `rationale`.

### 6.2 Session finalization
**Sent:** today's `PlannedSession` + `energyRating` + `timeAvailableMinutes`.
**Returned:** the trimmed/boosted `PlannedSession` (same schema).

### 6.3 Swap
**Sent:** the `exerciseID` to replace, current target, owned equipment,
exclusions.
**Returned:** 2–3 candidate `exerciseID`s + adjusted target load + one-line
reason each.

### 6.4 InBody extraction
**Sent:** the scan image.
**Returned:** the `InBodyScan` fields + a per-field / overall
`extractionConfidence`.

### Provider & model — abstraction, choice deferred

**`LLMProvider` protocol.** Minimal, provider-neutral surface:

```
protocol LLMProvider {
    // structured text completion
    func complete<T: Decodable>(
        system: String,
        user: String,
        schema: JSONSchema,
        as type: T.Type
    ) async throws -> LLMResult<T>

    // multimodal (InBody photo → fields); a provider without vision throws .unsupported
    func completeWithImage<T: Decodable>(
        system: String,
        user: String,
        image: ImagePayload,
        schema: JSONSchema,
        as type: T.Type
    ) async throws -> LLMResult<T>
}

struct LLMResult<T> {
    let value: T
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int
    let rawJSON: String
}
```

- **Four adapters ship**, one per `ProviderProfile.adapterKind`:
  `openAICompatible`, `gemini`, `anthropic`, `appleOnDevice`. No committed
  default model — selection criteria (reasoning quality, latency, cost/call) and
  candidates tracked in [05-open-questions.md](05-open-questions.md) Q8;
  cost modelling in [08-api-cost-analysis.md](08-api-cost-analysis.md).
- **The active model is a `ProviderProfile` chosen at runtime** (§3), not a
  build-time constant. A new vendor or model is adopted by adding/editing a
  profile in Settings — no app update. `openAICompatible` covers almost all
  future vendors (OpenRouter, Groq, DeepSeek, xAI, new first-party models…).
- `AIClient` resolves the active profile, picks the matching adapter, injects
  `baseURL` / `modelID` / key, and writes an `AICallRecord` (§3) after every
  call. `PlanCoordinator`, `RuleEngine`, `Validator`, request builders: untouched
  by any of this.
- Each adapter maps the single `JSONSchema` to its provider's native structured
  output (`responseSchema` / `response_format` / tool-use) and normalizes token
  counts (incl. cached) into `LLMResult`.
- **InBody vision:** if the active profile's `supportsVision` is false, `AIClient`
  routes `completeWithImage` to `AppSettings.visionProviderProfileID` if set,
  else surfaces "current model can't read images — pick one that can."
- **Phase 1** builds the four adapters against **one provisional seeded profile**
  (whichever model is fastest to stand up). Not a commitment.
- Adapters live behind the app's own request/response structs, so a provider that
  lacks strict schema enforcement is handled by the existing Validator +
  retry-once path (§7) rather than special-casing.

### 6.5 Call-volume & token estimate (deliberately high-side)

Sizing figures for provider selection and the token/cost meter. Full cost
modelling by model class in [08-api-cost-analysis.md](08-api-cost-analysis.md).
Assumes ~5
sessions/week (~22/month — the user's stated ceiling; real usage is often lower),
near-daily app opens, ~3 swaps per session. No prompt caching applied.

**Per-call size (high side):**

| Call | Input tokens | Output tokens | Main driver |
|------|-------------:|--------------:|-------------|
| Weekly plan generation | ~20,000 | ~3,000 | 4–6 wks history (~8k) + owned-equipment catalog slice (~5k) |
| Adjust remaining week | ~8,000 | ~1,000 | current plan + 1 wk history + partial catalog |
| Session finalization | ~2,500 | ~800 | today's session + energy/time |
| Swap | ~2,000 | ~300 | exercise + equipment + same-muscle catalog subset |
| Post-session feedback analysis | ~1,800 | ~400 | session log |
| InBody extraction | ~2,000 | ~500 | sheet photo image tokens + prompt |

**Monthly volume (high side):**

| Call | Count/mo | Input/mo | Output/mo |
|------|---------:|---------:|----------:|
| Weekly plan generation | 8 | 160,000 | 24,000 |
| Adjust remaining week | 30 | 240,000 | 30,000 |
| Session finalization | 22 | 55,000 | 17,600 |
| Swap | 66 | 132,000 | 19,800 |
| Post-session feedback analysis | 22 | 39,600 | 8,800 |
| InBody extraction | 1 | 2,000 | 500 |
| **Total** | **~150** | **~630,000** | **~100,000** |

**≈ 730K tokens/month → budget ~1M/month with margin → ~10–12M tokens/year.**

Levers that materially reduce this:

- **Prompt caching** — the system prompt and catalog slice are static; caching
  cuts monthly input toward ~200K on providers that support it.
- **Keep "adjust remaining week" rule-engine-only** (no LLM call) — removes ~38%
  of monthly input tokens (~630K → ~390K).
- **Rolling history window** caps per-call input as data accumulates — no
  unbounded growth.
- **Reasoning/thinking modes** multiply output tokens ~3–10×; account for this
  when picking a model.

---

## 7. Validation layer

Runs on **every** AI response before it touches storage or UI:

1. Every `exerciseID` exists in the catalog.
2. No excluded / injury-blocked exercise appears.
3. Every `targetLoadKg` increase vs. history is within the per-session cap.
4. Weekly working-set volume per muscle group sits inside the landmark band.
5. Rest-gap check passes.
6. JSON decodes cleanly into the expected struct.

**On failure:** `PlanCoordinator` retries **once**, feeding the specific
validation errors back into the prompt. Still failing → **fall back to the rule
engine alone**: use the templates + last week's plan advanced by the progression
rule. The user always gets a workout. `WeeklyPlan.source` records `ai` vs.
`fallback`.

---

## 8. Failure handling

| Situation | Behaviour |
|-----------|-----------|
| **No API key** | Onboarding blocks on adding one, with a link to where to get it. Everything except AI calls still works. |
| **Offline** | The active `WeeklyPlan` and every `PlannedSession` live in SwiftData. **Browsing planned workouts, running a session, logging sets, and manual (rule-engine) swaps all work fully offline.** Only generation / adjustment / AI-swap need network — those queue and run on reconnect. An offline indicator shows the cached plan is in use. |
| **API error / timeout / rate limit** | One retry → rule-engine fallback → quiet "coach unavailable, used the backup plan" note. Logs are saved locally first, never at risk. |
| **AI response fails validation** | §7 — retry with errors, then fallback. |
| **Bad InBody photo** (low confidence) | Skip the confirm screen's pre-fill; open manual entry instead. |
| **Catalog gap** (AI wants an exercise we don't have) | Rejected by Validator; retry asks for an in-catalog choice. |

### 8.1 Real-time cost tracking

Every LLM call writes an `AICallRecord` (§3) with token counts and a `costUSD`
computed from the active `ProviderProfile`'s price fields. Surfaces:

- **Persistent** — a month-to-date `$` chip in the app (Plan screen header).
- **Per generation** — a one-line note after a plan/adjust/swap:
  *"Coach updated · ~$0.004"*.
- **Settings → Usage & Cost** — month-to-date + all-time totals, breakdown by
  `callType`, 30-day sparkline, call count and average cost/call. The editable
  price fields live on each `ProviderProfile`.

**Budget control (optional):** `AppSettings.monthlyBudgetUSD`. Soft warning
banner at 80% and 100% of it. Toggle `pauseAIWhenOverBudget` (default **off**):
when on and the month's cost reaches 100%, `PlanCoordinator` stops making AI
calls and uses the rule-engine fallback until month rollover; when off, calls
continue and only the banner shows.

---

## 9. Testing

| Target | Method |
|--------|--------|
| **RuleEngine** (templates, landmarks, progression, load caps, swap search, rest-gap) | Plain unit tests. Highest coverage — this is the safety-critical code. No AI, no UI. |
| **Validator** | Unit tests with hand-built good/bad `WeeklyPlan` fixtures for each of the 6 checks. |
| **AI response handling** | Recorded / mocked JSON: valid, malformed, invalid exercise id, unsafe load jump → assert retry-then-fallback. |
| **Provider adapters** | Against recorded HTTP fixtures per `adapterKind`: schema mapping, token/cached-count normalization into `LLMResult`, vision-unsupported routing. |
| **Cost ledger** | `costUSD` computed correctly from profile prices; month-to-date / per-`callType` aggregations; `pauseAIWhenOverBudget` gates AI calls at 100%. |
| **InBodyExtractor** | Mocked vision responses + a handful of real scan photos checked by hand during development. |
| **PersistenceStore** | SwiftData round-trip tests for the core models (incl. `ProviderProfile`, `AICallRecord`). |
| **Acceptance** | Varun running real sessions in his actual gym. The real test. |

---

## 10. Project structure

**Xcode app project + local Swift packages** for the pure-logic modules. The
domain logic (`RuleEngine`, `Validator`, catalog model + `CatalogStore`, the
`LLMProvider` protocol and request/response types) lives in a local SPM package
with no UIKit/SwiftUI/SwiftData dependency, so it builds and tests on its own in
seconds without the app or a simulator. The Xcode target holds SwiftUI views,
SwiftData models, persistence, notifications, and the concrete provider adapter,
and depends on the package.

```
fitness-tracker-ios/
├── README.md
├── docs/                       # these design docs
├── FitnessCore/                # local Swift package — pure, no Apple UI frameworks
│   ├── Sources/
│   │   ├── RuleEngine/         # templates, volume landmarks, progression, swap search, rest-gap
│   │   ├── Validation/         # Validator
│   │   ├── Catalog/            # Exercise model + CatalogStore + catalog.json loader
│   │   └── LLM/                # LLMProvider protocol, JSONSchema, request/response structs
│   └── Tests/                  # fast unit tests for all of the above
├── App/                        # Xcode app target
│   ├── FitnessTrackerApp.swift
│   ├── Models/                 # SwiftData @Model types
│   ├── AI/                     # concrete provider adapter(s) + AIClient (1 provisional in Phase 1)
│   ├── Coordination/           # PlanCoordinator
│   ├── Persistence/            # PersistenceStore
│   ├── Notifications/
│   ├── Resources/              # catalog.json + image assets
│   └── Features/               # SwiftUI views: Onboarding / Plan / Session / InBody / Settings
└── AppTests/                   # SwiftData round-trip, coordinator, adapter tests
```
