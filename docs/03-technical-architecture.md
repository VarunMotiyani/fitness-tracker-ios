# 03 — Technical Architecture

_Date: 2026-08-27_

Behaviour is in [02-product-design.md](02-product-design.md). This doc is the
"how it's built."

---

## 1. Stack

| Layer | Choice | Why |
|-------|--------|-----|
| UI | **SwiftUI**, iOS 17+ | Native, first-party, fastest path for an experienced engineer on their first iOS app. |
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
`apiKeyRef` (Keychain ref), `notificationPrefs`, `monthToDateTokenCost`,
`llmProvider` (enum: gemini / openai / anthropic / router / local — extensible),
`modelName`, `pricePerMTokIn` / `pricePerMTokOut` (so the cost meter is right for
whatever model is chosen).

---

## 4. Exercise catalog

- Sourced from an open dataset (e.g. a public-domain / permissively licensed
  exercise DB with instruction images). License recorded in the repo.
- **v1: a curated ~100–150 exercises** covering every major movement pattern
  across barbell / dumbbell / machine / cable / bodyweight.
- Shipped as `catalog.json` + an image asset folder in the app bundle.
- `CatalogStore` loads it once, indexes by `id`, `primaryMuscle`,
  `requiredEquipment`, `movementPattern`.
- Growth path: pull more entries from the ~800-exercise dataset as gaps show up.
- **Hard rule:** the AI may only prescribe `exerciseID`s that exist in the
  catalog. Anything else is rejected by the Validator.

---

## 5. Rule engine

Pure functions. No network, no storage.

- **Split templates** — full body, upper/lower, PPL, Arnold. Each defines session
  count, per-session focus muscles, and set/rep scheme bands. The engine picks a
  template from experience + weekly capacity + goal.
- **Volume landmarks** — per muscle group, per experience level: weekly min /
  target / max working-set counts. All AI plans and adaptations are clamped into
  this band.
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

struct LLMResult<T> { let value: T; let inputTokens: Int; let outputTokens: Int; let rawJSON: String }
```

- **No committed provider or model.** Selection criteria: reasoning quality,
  latency, cost per call. Candidates to benchmark later: Gemini Flash-class,
  GPT-mini-class, Claude Haiku-class, an OpenRouter-style router, or a local
  model. Decision tracked in [05-open-questions.md](05-open-questions.md) Q8.
- Each adapter maps the single `JSONSchema` to its provider's native structured
  output (`responseSchema` / `response_format` / tool-use) and normalizes token
  counts into `LLMResult` for the cost meter.
- `provider` and `modelName` are `AppSettings` values — switching is config only;
  `PlanCoordinator`, `RuleEngine`, `Validator`, and every request builder are
  untouched.
- **Phase 1 builds one provisional adapter** (whichever is fastest to stand up)
  purely to develop and test against. It is not a commitment.
- Adapters live behind the app's own request/response structs, so a provider that
  lacks strict schema enforcement is handled by the existing Validator +
  retry-once path (§7) rather than special-casing.

### 6.5 Call-volume & token estimate (deliberately high-side)

Sizing figures for provider selection and the token/cost meter. Assumes ~5
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
| **Offline** | Current week + today's session are cached in SwiftData → training and logging work fully offline. Plan regeneration queues and runs on reconnect. |
| **API error / timeout / rate limit** | One retry → rule-engine fallback → quiet "coach unavailable, used the backup plan" note. Logs are saved locally first, never at risk. |
| **AI response fails validation** | §7 — retry with errors, then fallback. |
| **Bad InBody photo** (low confidence) | Skip the confirm screen's pre-fill; open manual entry instead. |
| **Catalog gap** (AI wants an exercise we don't have) | Rejected by Validator; retry asks for an in-catalog choice. |

**Cost visibility:** every AI call's token usage is accumulated into
`monthToDateTokenCost`, shown in Settings, reset monthly.

---

## 9. Testing

| Target | Method |
|--------|--------|
| **RuleEngine** (templates, landmarks, progression, load caps, swap search, rest-gap) | Plain unit tests. Highest coverage — this is the safety-critical code. No AI, no UI. |
| **Validator** | Unit tests with hand-built good/bad `WeeklyPlan` fixtures for each of the 6 checks. |
| **AI response handling** | Recorded / mocked JSON: valid, malformed, invalid exercise id, unsafe load jump → assert retry-then-fallback. |
| **InBodyExtractor** | Mocked vision responses + a handful of real scan photos checked by hand during development. |
| **PersistenceStore** | SwiftData round-trip tests for the core models. |
| **Acceptance** | Varun running real sessions in his actual gym. The real test. |

---

## 10. Repo layout (proposed)

```
fitness-tracker-ios/
├── README.md
├── docs/                     # these design docs
├── App/
│   ├── FitnessTrackerApp.swift
│   ├── Models/               # SwiftData @Model types
│   ├── Catalog/              # catalog.json + images + CatalogStore
│   ├── RuleEngine/           # pure logic + tests
│   ├── AI/                   # LLMProvider protocol + adapters (1 provisional in Phase 1), AIClient, request builders, response structs
│   ├── Validation/           # Validator + tests
│   ├── Coordination/         # PlanCoordinator
│   ├── Persistence/          # PersistenceStore
│   ├── Notifications/
│   └── Features/             # SwiftUI views by feature
│       ├── Onboarding/
│       ├── Plan/
│       ├── Session/
│       ├── InBody/
│       └── Settings/
└── FitnessTrackerTests/
```
