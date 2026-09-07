# Phase 1c — AI Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline, matching Phase 1b) or superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** The app generates the weekly plan with an LLM — user-managed provider profiles (OpenAI-compatible, Gemini, Apple on-device), a coordinator that validates the AI plan and falls back to the rule engine, and a real-time cost ledger.

**Architecture:** All app-side; `FitnessCore` is unchanged. `ProviderProfile` (SwiftData) holds a user-editable provider config; a `KeychainStore` holds the API key; concrete `LLMProvider` adapters (`OpenAICompatibleProvider`, `GeminiProvider`, `FoundationModelsProvider`) implement the `FitnessCore.LLMKit` protocol; `LLMProviderFactory` builds one from the active profile; `PlanCoordinator` runs *AI generate → `PlanValidator` → retry once → `RulePlanBuilder` fallback*, recording an `AICallRecord`. Onboarding "Create my plan" and Settings "Regenerate" route through the coordinator instead of `PlanService`.

**Tech Stack:** Swift 6 / language mode v6, SwiftUI, SwiftData, Foundation `URLSession`, `Security` (Keychain), `FoundationModels` (guarded by `#if canImport`), Swift Testing with a `URLProtocol` stub for HTTP adapters. iOS 26.

**Spec:** `docs/02-product-design.md` §9, `docs/03-technical-architecture.md` §3 (`ProviderProfile`, `AICallRecord`), §6 (`LLMProvider`, adapters, §6.5 volume), §6.1–6.5 AI contract, §7 validation, §8.1 cost tracking. `docs/06-decisions.md` A4, A5, A11–A13. `docs/08-api-cost-analysis.md`. `FitnessCore/LLMKit` (the protocol, from 1a).

## Global Constraints

- **`FitnessCore` is NOT modified.** If a change there seems needed, stop and raise it.
- **No AI call is ever required.** With no active profile, or on any adapter failure, the coordinator returns a rule-engine plan. The app is fully usable offline with zero configuration.
- **Xcode 26 default actor isolation is `@MainActor`** for the app module. Pure-logic types (`PlanCoordinator`, `KeychainStore`, `LLMProviderFactory`, `PlanPromptBuilder`, adapters, DTO mappers, `CostSummary`) are `nonisolated`. SwiftData `@Model` tests and `@Observable`/UI tests are `@MainActor`.
- **Adapters own only transport + schema mapping.** They take `system`/`user`/`schema` and return a decoded `LLMResult<Value>`. They know nothing about training, `WeeklyPlan`, or the coordinator.
- **Secrets:** API keys live only in the Keychain (`KeychainStore`), referenced by `ProviderProfile.apiKeyRef`. Never store a key in a SwiftData column, a log, or a commit.
- **Structured output:** each adapter uses its provider's native JSON mode (`response_format: json_schema` / `responseSchema` / `@Generable`). The coordinator still validates and retries — never trust the model's JSON blindly.
- **`nonisolated` on pure enums/structs** as in Phase 1b.
- **Networking:** `URLSession` only, `async/await`. Tests inject a stub via `URLSessionConfiguration.protocolClasses`. No real network call in any test.
- **Commit style:** plain imperative subject, no body, **no `Co-Authored-By` trailer**. Do **not** `git push`.
- **Branch:** `phase-1c-ai-integration` from `main`.
- **Adapters shipped in 1c:** `openAICompatible`, `gemini` (AI Studio), `appleOnDevice`. Deferred one-task follow-ups (documented, not built): native Anthropic, Gemini Vertex/GCP service-account auth, AWS Bedrock (SigV4).

## File Structure

```
FitnessTracker/FitnessTracker/
├── Models/
│   ├── ProviderProfile.swift        # @Model + AdapterKind + active-profile helpers
│   └── AICallRecord.swift           # @Model + cost math
├── AI/
│   ├── KeychainStore.swift          # SecItem wrapper
│   ├── LLMProviderFactory.swift     # ProviderProfile (+ key) -> any LLMProvider
│   ├── PlanDTO.swift                # WeeklyPlanDTO (Codable) + toDomain() + planJSONSchema
│   ├── PlanPromptBuilder.swift      # UserContext + catalog slice -> system/user
│   ├── PlanCoordinator.swift        # generate -> validate -> retry -> fallback
│   ├── CostSummary.swift            # aggregate AICallRecord
│   └── Adapters/
│       ├── OpenAICompatibleProvider.swift
│       ├── GeminiProvider.swift
│       └── FoundationModelsProvider.swift   # #if canImport(FoundationModels)
├── Features/Settings/
│   ├── SettingsView.swift           # (edit) real AI section + Usage
│   ├── ProviderProfileListView.swift
│   └── ProviderProfileEditView.swift
├── Features/Plan/PlanView.swift     # (edit) $ chip
├── RootView.swift                   # (edit) route through PlanCoordinator
└── FitnessTrackerApp.swift          # (edit) add ProviderProfile.self, AICallRecord.self
FitnessTracker/FitnessTrackerTests/
├── StubLLMProvider.swift
├── StubURLProtocol.swift
├── ProviderProfileTests.swift
├── KeychainStoreTests.swift
├── PlanDTOTests.swift
├── PlanPromptBuilderTests.swift
├── PlanCoordinatorTests.swift
├── OpenAICompatibleProviderTests.swift
├── GeminiProviderTests.swift
├── LLMProviderFactoryTests.swift
├── AICallRecordTests.swift
└── CostSummaryTests.swift
```

---

## Task 1: ProviderProfile SwiftData model

**Files:**
- Create: `Models/ProviderProfile.swift`
- Modify: `FitnessTrackerApp.swift`
- Test: `FitnessTrackerTests/ProviderProfileTests.swift`

**Interfaces:**
- Produces:
  - `enum AdapterKind: String, Codable, Sendable, CaseIterable { case openAICompatible, gemini, appleOnDevice }` (marked `nonisolated`)
  - `@Model final class ProviderProfile` — `displayName: String`, `adapterKindRaw: String`, `baseURL: String?`, `modelID: String`, `apiKeyRef: String?`, `supportsVision: Bool`, `pricePerMTokIn: Double`, `pricePerMTokOut: Double`, `pricePerMTokCached: Double`, `isActive: Bool`, `createdAt: Date`
  - convenience: `var adapterKind: AdapterKind { AdapterKind(rawValue: adapterKindRaw) ?? .appleOnDevice }`
  - `init(displayName:adapterKind:baseURL:modelID:apiKeyRef:supportsVision:pricePerMTokIn:pricePerMTokOut:pricePerMTokCached:)` — `isActive = false`, `createdAt = .now`

- [ ] **Step 1: Failing test** — `ProviderProfileTests.swift`

```swift
import Testing
import SwiftData
@testable import FitnessTracker

@MainActor
struct ProviderProfileTests {
    @Test func roundTripsAndExposesAdapterKind() throws {
        let container = try ModelContainer(for: ProviderProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        let p = ProviderProfile(displayName: "Local Ollama", adapterKind: .openAICompatible,
            baseURL: "http://localhost:11434/v1", modelID: "llama3.2",
            apiKeyRef: nil, supportsVision: false,
            pricePerMTokIn: 0, pricePerMTokOut: 0, pricePerMTokCached: 0)
        ctx.insert(p); try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<ProviderProfile>()).first
        #expect(fetched?.adapterKind == .openAICompatible)
        #expect(fetched?.baseURL == "http://localhost:11434/v1")
        #expect(fetched?.isActive == false)
    }

    @Test func unknownAdapterKindFallsBack() {
        let p = ProviderProfile(displayName: "x", adapterKind: .gemini, baseURL: nil,
            modelID: "m", apiKeyRef: nil, supportsVision: false,
            pricePerMTokIn: 0, pricePerMTokOut: 0, pricePerMTokCached: 0)
        p.adapterKindRaw = "nonsense"
        #expect(p.adapterKind == .appleOnDevice)
    }
}
```

- [ ] **Step 2: Run — expect FAIL.** `xcodebuild test -scheme FitnessTracker -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:FitnessTrackerTests`

- [ ] **Step 3: Write `ProviderProfile.swift`**

```swift
import Foundation
import SwiftData

nonisolated enum AdapterKind: String, Codable, Sendable, CaseIterable {
    case openAICompatible
    case gemini
    case appleOnDevice
}

@Model
final class ProviderProfile {
    var displayName: String
    var adapterKindRaw: String
    var baseURL: String?
    var modelID: String
    var apiKeyRef: String?
    var supportsVision: Bool
    var pricePerMTokIn: Double
    var pricePerMTokOut: Double
    var pricePerMTokCached: Double
    var isActive: Bool
    var createdAt: Date

    var adapterKind: AdapterKind { AdapterKind(rawValue: adapterKindRaw) ?? .appleOnDevice }

    init(displayName: String,
         adapterKind: AdapterKind,
         baseURL: String?,
         modelID: String,
         apiKeyRef: String?,
         supportsVision: Bool,
         pricePerMTokIn: Double,
         pricePerMTokOut: Double,
         pricePerMTokCached: Double) {
        self.displayName = displayName
        self.adapterKindRaw = adapterKind.rawValue
        self.baseURL = baseURL
        self.modelID = modelID
        self.apiKeyRef = apiKeyRef
        self.supportsVision = supportsVision
        self.pricePerMTokIn = pricePerMTokIn
        self.pricePerMTokOut = pricePerMTokOut
        self.pricePerMTokCached = pricePerMTokCached
        self.isActive = false
        self.createdAt = .now
    }
}
```

- [ ] **Step 4: `FitnessTrackerApp.swift`** — `.modelContainer(for: [UserProfile.self, StoredPlan.self, ProviderProfile.self, AICallRecord.self])` (add `AICallRecord.self` now too; it's created in Task 12 — until then use `[UserProfile.self, StoredPlan.self, ProviderProfile.self]` and add `AICallRecord.self` in Task 12).

- [ ] **Step 5: Run — expect PASS.**

- [ ] **Step 6: Commit** — `git add FitnessTracker && git commit -m "Add ProviderProfile SwiftData model"`

---

## Task 2: KeychainStore

**Files:**
- Create: `AI/KeychainStore.swift`
- Test: `FitnessTrackerTests/KeychainStoreTests.swift`

**Interfaces:**
- Produces `nonisolated enum KeychainStore`:
  - `static func set(_ value: String, account: String) throws`
  - `static func get(account: String) throws -> String?`
  - `static func delete(account: String) throws`
  - `enum KeychainError: Error, Equatable { case unexpectedStatus(OSStatus) }`
  - Service constant: `"com.varunmotiyani.FitnessTracker.apikeys"`

- [ ] **Step 1: Failing test**

```swift
import Testing
@testable import FitnessTracker

struct KeychainStoreTests {
    @Test func setGetDeleteRoundTrip() throws {
        let account = "test-\(UUID().uuidString)"
        defer { try? KeychainStore.delete(account: account) }

        #expect(try KeychainStore.get(account: account) == nil)
        try KeychainStore.set("sk-abc123", account: account)
        #expect(try KeychainStore.get(account: account) == "sk-abc123")
        try KeychainStore.set("sk-xyz789", account: account)          // overwrite
        #expect(try KeychainStore.get(account: account) == "sk-xyz789")
        try KeychainStore.delete(account: account)
        #expect(try KeychainStore.get(account: account) == nil)
    }
}
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Write `KeychainStore.swift`**

```swift
import Foundation
import Security

nonisolated enum KeychainStore {
    enum KeychainError: Error, Equatable {
        case unexpectedStatus(OSStatus)
    }

    private static let service = "com.varunmotiyani.FitnessTracker.apikeys"

    static func set(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func get(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.unexpectedStatus(status)
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
```

- [ ] **Step 4: Run — expect PASS.** (The simulator has a working keychain.)

- [ ] **Step 5: Commit** — `git commit -m "Add KeychainStore for API keys"`

---

## Task 3: WeeklyPlanDTO + schema + domain mapping

**Files:**
- Create: `AI/PlanDTO.swift`
- Test: `FitnessTrackerTests/PlanDTOTests.swift`

**Interfaces:**
- Produces (all `nonisolated`):
  - `struct WeeklyPlanDTO: Codable, Sendable, Equatable` with:
    - `rationale: String`
    - `sessions: [SessionDTO]` where `SessionDTO { order: Int; focusMuscles: [String]; items: [ItemDTO] }`
    - `ItemDTO { exerciseID: String; sets: Int; repMin: Int; repMax: Int; restSeconds: Int; coachNote: String }`
    - `weeklyVolumeTargets: [VolumeDTO]` where `VolumeDTO { muscle: String; targetSets: Int }`
  - `func toDomain(weekStartDate: Date, source: PlanSource) -> WeeklyPlan` — maps strings→`MuscleGroup` (drop unmappable), `targetLoadKg` always `nil`, fresh `UUID` per session
  - `static let planJSONSchema: JSONSchema` — a JSON-schema string describing `WeeklyPlanDTO` (object → sessions array → items array; all fields required; `additionalProperties: false`)

- [ ] **Step 1: Failing test**

```swift
import Testing
import Foundation
import FitnessDomain
import LLMKit
@testable import FitnessTracker

struct PlanDTOTests {
    private let json = """
    {"rationale":"4-day upper/lower",
     "sessions":[{"order":0,"focusMuscles":["chest","back"],
       "items":[{"exerciseID":"Barbell_Bench_Press","sets":3,"repMin":8,"repMax":12,
                 "restSeconds":150,"coachNote":"Leave 2 in the tank."}]}],
     "weeklyVolumeTargets":[{"muscle":"chest","targetSets":16},{"muscle":"nonsense","targetSets":9}]}
    """.data(using: .utf8)!

    @Test func decodesAndMapsToDomain() throws {
        let dto = try JSONDecoder().decode(WeeklyPlanDTO.self, from: json)
        let plan = dto.toDomain(weekStartDate: Date(timeIntervalSince1970: 0), source: .ai)

        #expect(plan.source == .ai)
        #expect(plan.rationale == "4-day upper/lower")
        #expect(plan.sessions.count == 1)
        #expect(plan.sessions[0].focusMuscles == [.chest, .back])
        #expect(plan.sessions[0].items[0].exerciseID == "Barbell_Bench_Press")
        #expect(plan.sessions[0].items[0].targetReps == RepRange(min: 8, max: 12))
        #expect(plan.sessions[0].items[0].targetLoadKg == nil)
        // "nonsense" muscle dropped from volume targets
        #expect(plan.weeklyVolumeTargets.map(\.muscle) == [.chest])
    }

    @Test func schemaIsNonEmptyJSON() {
        #expect(WeeklyPlanDTO.planJSONSchema.json.contains("\"sessions\""))
        #expect(WeeklyPlanDTO.planJSONSchema.json.contains("\"exerciseID\""))
    }
}
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Write `PlanDTO.swift`**

```swift
import Foundation
import FitnessDomain
import LLMKit

nonisolated struct WeeklyPlanDTO: Codable, Sendable, Equatable {
    struct ItemDTO: Codable, Sendable, Equatable {
        var exerciseID: String
        var sets: Int
        var repMin: Int
        var repMax: Int
        var restSeconds: Int
        var coachNote: String
    }
    struct SessionDTO: Codable, Sendable, Equatable {
        var order: Int
        var focusMuscles: [String]
        var items: [ItemDTO]
    }
    struct VolumeDTO: Codable, Sendable, Equatable {
        var muscle: String
        var targetSets: Int
    }

    var rationale: String
    var sessions: [SessionDTO]
    var weeklyVolumeTargets: [VolumeDTO]

    func toDomain(weekStartDate: Date, source: PlanSource) -> WeeklyPlan {
        let mappedSessions = sessions.map { s in
            PlannedSession(
                id: UUID(),
                order: s.order,
                focusMuscles: s.focusMuscles.compactMap { MuscleGroup(rawValue: $0) },
                items: s.items.map { i in
                    PlannedItem(exerciseID: i.exerciseID,
                                targetSets: i.sets,
                                targetReps: RepRange(min: i.repMin, max: i.repMax),
                                targetLoadKg: nil,
                                restSeconds: i.restSeconds,
                                coachNote: i.coachNote)
                }
            )
        }
        let targets = weeklyVolumeTargets.compactMap { v -> MuscleVolumeTarget? in
            guard let m = MuscleGroup(rawValue: v.muscle) else { return nil }
            return MuscleVolumeTarget(muscle: m, targetSets: v.targetSets)
        }
        return WeeklyPlan(weekStartDate: weekStartDate, source: source,
                          rationale: rationale, sessions: mappedSessions,
                          weeklyVolumeTargets: targets)
    }

    static let planJSONSchema = JSONSchema(json: #"""
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["rationale", "sessions", "weeklyVolumeTargets"],
      "properties": {
        "rationale": { "type": "string" },
        "sessions": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["order", "focusMuscles", "items"],
            "properties": {
              "order": { "type": "integer" },
              "focusMuscles": { "type": "array", "items": { "type": "string" } },
              "items": {
                "type": "array",
                "items": {
                  "type": "object",
                  "additionalProperties": false,
                  "required": ["exerciseID", "sets", "repMin", "repMax", "restSeconds", "coachNote"],
                  "properties": {
                    "exerciseID": { "type": "string" },
                    "sets": { "type": "integer" },
                    "repMin": { "type": "integer" },
                    "repMax": { "type": "integer" },
                    "restSeconds": { "type": "integer" },
                    "coachNote": { "type": "string" }
                  }
                }
              }
            }
          }
        },
        "weeklyVolumeTargets": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["muscle", "targetSets"],
            "properties": {
              "muscle": { "type": "string" },
              "targetSets": { "type": "integer" }
            }
          }
        }
      }
    }
    """#)
}
```

- [ ] **Step 4: Run — expect PASS.**

- [ ] **Step 5: Commit** — `git commit -m "Add WeeklyPlanDTO, JSON schema, and domain mapping"`

---

## Task 4: PlanPromptBuilder

**Files:**
- Create: `AI/PlanPromptBuilder.swift`
- Test: `FitnessTrackerTests/PlanPromptBuilderTests.swift`

**Interfaces:**
- Produces `nonisolated struct PlanPromptBuilder`:
  - `init(catalog: CatalogStore)`
  - `func system() -> String` — the coaching-system instruction (rules: use only the given exercise IDs; balance volume to the landmark hints; output must match the schema; no prose outside JSON)
  - `func user(context: UserContext, priorIssues: [String] = []) -> String` — profile summary + the **owned-equipment catalog slice** (id · name · primaryMuscle · equipment · mechanic, one per line, only exercises whose `equipment ∈ context.availableEquipment` and `id ∉ context.excludedExerciseIDs` and `primaryMuscle ∉ context.excludedMuscles`) + volume-landmark hints (per in-scope muscle: `mev–mrv` from `VolumeLandmarks`) + `sessionsPerWeek` / `sessionLengthMinutes` + goal + experience. If `priorIssues` is non-empty, append a "Your previous attempt had these problems, fix them:" block.

- [ ] **Step 1: Failing test**

```swift
import Testing
import FitnessDomain
import ExerciseCatalog
import RuleEngine
@testable import FitnessTracker

struct PlanPromptBuilderTests {
    private func builder() throws -> PlanPromptBuilder {
        PlanPromptBuilder(catalog: try BundledCatalog.load())
    }
    private func ctx(equipment: Set<Equipment> = [.barbell, .dumbbell]) -> UserContext {
        UserContext(goal: .buildMuscle, experience: .intermediate, sessionsPerWeek: 4,
                    sessionLengthMinutes: 60, availableEquipment: equipment,
                    excludedExerciseIDs: ["Barbell_Bench_Press"], excludedMuscles: [.calves])
    }

    @Test func userPromptOnlyListsOwnedNonExcludedExercises() throws {
        let u = try builder().user(context: ctx())
        #expect(u.contains("Dumbbell_Bench_Press"))       // dumbbell, owned
        #expect(!u.contains("Barbell_Bench_Press"))        // excluded id
        #expect(!u.contains("Standing_Calf_Raise"))        // machine (not owned) AND calves (excluded)
        #expect(!u.contains("Cable_Crossover"))            // cable not owned
        #expect(u.contains("60"))                          // session length
    }

    @Test func priorIssuesAppended() throws {
        let u = try builder().user(context: ctx(), priorIssues: ["session 2 was empty"])
        #expect(u.localizedCaseInsensitiveContains("previous attempt"))
        #expect(u.contains("session 2 was empty"))
    }

    @Test func systemMentionsSchemaAndIDConstraint() throws {
        let s = try builder().system()
        #expect(s.localizedCaseInsensitiveContains("only") && s.localizedCaseInsensitiveContains("exercise"))
        #expect(s.localizedCaseInsensitiveContains("json"))
    }
}
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Write `PlanPromptBuilder.swift`**

```swift
import Foundation
import FitnessDomain
import ExerciseCatalog
import RuleEngine

nonisolated struct PlanPromptBuilder {
    let catalog: CatalogStore

    init(catalog: CatalogStore) { self.catalog = catalog }

    func system() -> String {
        """
        You are a strength & physique coach. Build one week of training.
        Hard rules:
        - Use ONLY the exercise IDs listed in the user message. Never invent an ID.
        - Keep each muscle's weekly working sets within the min–max hints given.
        - Give every session a non-empty item list.
        - Respond with a single JSON object matching the provided schema. No prose, no markdown, no code fences.
        """
    }

    func user(context: UserContext, priorIssues: [String] = []) -> String {
        let inScopeMuscles = MuscleGroup.allCases.filter { !context.excludedMuscles.contains($0) }

        let slice = catalog.all
            .filter { context.availableEquipment.contains($0.equipment) }
            .filter { !context.excludedExerciseIDs.contains($0.id) }
            .filter { !context.excludedMuscles.contains($0.primaryMuscle) }
            .sorted { $0.id < $1.id }
            .map { "\($0.id) | \($0.name) | \($0.primaryMuscle.rawValue) | \($0.equipment.rawValue) | \($0.mechanic.rawValue)" }
            .joined(separator: "\n")

        let landmarks = inScopeMuscles.map { m -> String in
            let b = VolumeLandmarks.band(for: m, experience: context.experience)
            return "\(m.rawValue): \(b.mev)–\(b.mrv) sets/week (aim ~\(b.mav))"
        }.joined(separator: "\n")

        var out = """
        Goal: \(context.goal.rawValue)
        Experience: \(context.experience.rawValue)
        Sessions per week: \(context.sessionsPerWeek)
        Session length: \(context.sessionLengthMinutes) minutes

        Available exercises (ID | name | primary muscle | equipment | mechanic):
        \(slice)

        Weekly volume hints:
        \(landmarks)
        """

        if !priorIssues.isEmpty {
            out += "\n\nYour previous attempt had these problems — fix all of them:\n"
            out += priorIssues.map { "- \($0)" }.joined(separator: "\n")
        }
        return out
    }
}
```

- [ ] **Step 4: Run — expect PASS.**

- [ ] **Step 5: Commit** — `git commit -m "Add PlanPromptBuilder"`

---

## Task 5: Stub test doubles (LLMProvider + URLProtocol)

**Files:**
- Create: `FitnessTrackerTests/StubLLMProvider.swift`
- Create: `FitnessTrackerTests/StubURLProtocol.swift`

**Interfaces:**
- Produces:
  - `final class StubLLMProvider: LLMProvider, @unchecked Sendable` — configurable: `var responses: [Result<String, LLMError>]` (JSON strings or errors, consumed FIFO), `var inputTokens`, `var outputTokens`. `complete` pops the next response, decodes the JSON to `Value` on success, throws on error/empty. `completeWithImage` throws `.visionUnsupported`. Tracks `callCount`.
  - `final class StubURLProtocol: URLProtocol` — class-level `static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?`; standard `URLProtocol` overrides; helper `static func session() -> URLSession` returning a session configured with `protocolClasses = [StubURLProtocol.self]`.

- [ ] **Step 1: Write `StubLLMProvider.swift`**

```swift
import Foundation
import LLMKit

final class StubLLMProvider: LLMProvider, @unchecked Sendable {
    var responses: [Result<String, LLMError>]
    var inputTokens = 10
    var outputTokens = 20
    private(set) var callCount = 0
    private(set) var lastUser = ""

    init(responses: [Result<String, LLMError>]) { self.responses = responses }

    func complete<Value: Decodable & Sendable>(system: String, user: String,
                                               schema: JSONSchema,
                                               as type: Value.Type) async throws -> LLMResult<Value> {
        callCount += 1
        lastUser = user
        guard !responses.isEmpty else { throw LLMError.emptyResponse }
        switch responses.removeFirst() {
        case .failure(let e): throw e
        case .success(let json):
            let data = Data(json.utf8)
            let value = try JSONDecoder().decode(Value.self, from: data)
            return LLMResult(value: value, inputTokens: inputTokens, outputTokens: outputTokens,
                             cachedTokens: 0, rawJSON: json)
        }
    }

    func completeWithImage<Value: Decodable & Sendable>(system: String, user: String,
                                                        image: ImagePayload, schema: JSONSchema,
                                                        as type: Value.Type) async throws -> LLMResult<Value> {
        throw LLMError.visionUnsupported
    }
}
```

- [ ] **Step 2: Write `StubURLProtocol.swift`**

```swift
import Foundation

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}
```

- [ ] **Step 3: Build the test target** — no test yet, just confirm it compiles: `xcodebuild build-for-testing -scheme FitnessTracker -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.

- [ ] **Step 4: Commit** — `git commit -m "Add StubLLMProvider and StubURLProtocol test doubles"`

---

## Task 6: PlanCoordinator — happy path

**Files:**
- Create: `AI/PlanCoordinator.swift`
- Test: `FitnessTrackerTests/PlanCoordinatorTests.swift`

**Interfaces:**
- Produces (`nonisolated`):
  - `struct CallOutcome: Sendable, Equatable { let inputTokens: Int; let outputTokens: Int; let cachedTokens: Int; let succeeded: Bool }`
  - `struct CoordinatorResult: Sendable { let plan: WeeklyPlan; let source: PlanSource; let issues: [ValidationIssue]; let call: CallOutcome? }`
  - `struct PlanCoordinator`:
    - `init(provider: (any LLMProvider)?, catalog: CatalogStore)`
    - `func makePlan(context: UserContext, weekStartDate: Date) async -> CoordinatorResult`
  - Behaviour (this task: happy path only): if `provider == nil` → rule engine, `source: .ruleEngine`, `call: nil`. If provider present → `complete(as: WeeklyPlanDTO.self)`, `dto.toDomain(source: .ai)`, validate; if `issues.isEmpty` → return `.ai` + `CallOutcome(succeeded: true)`.

- [ ] **Step 1: Failing test**

```swift
import Testing
import Foundation
import FitnessDomain
import ExerciseCatalog
@testable import FitnessTracker

struct PlanCoordinatorTests {
    private func catalog() throws -> ExerciseCatalog.CatalogStore { try BundledCatalog.load() }
    private func ctx() -> UserContext {
        UserContext(goal: .buildMuscle, experience: .intermediate, sessionsPerWeek: 3,
                    sessionLengthMinutes: 60,
                    availableEquipment: [.barbell, .dumbbell, .cable, .machine],
                    excludedExerciseIDs: [], excludedMuscles: [])
    }
    /// A DTO the stub returns that is valid against the stub catalog + a 3-day full body context.
    private let validDTOJSON = """
    {"rationale":"3-day full body",
     "sessions":[
       {"order":0,"focusMuscles":["chest","back","quads"],"items":[
         {"exerciseID":"Barbell_Bench_Press","sets":4,"repMin":8,"repMax":12,"restSeconds":150,"coachNote":"x"},
         {"exerciseID":"Barbell_Row","sets":4,"repMin":8,"repMax":12,"restSeconds":150,"coachNote":"x"},
         {"exerciseID":"Barbell_Back_Squat","sets":4,"repMin":8,"repMax":12,"restSeconds":150,"coachNote":"x"}]},
       {"order":1,"focusMuscles":["chest","back","quads"],"items":[
         {"exerciseID":"Dumbbell_Bench_Press","sets":4,"repMin":8,"repMax":12,"restSeconds":150,"coachNote":"x"},
         {"exerciseID":"Seated_Cable_Row","sets":4,"repMin":8,"repMax":12,"restSeconds":150,"coachNote":"x"},
         {"exerciseID":"Leg_Press","sets":4,"repMin":8,"repMax":12,"restSeconds":150,"coachNote":"x"}]},
       {"order":2,"focusMuscles":["chest","back","quads"],"items":[
         {"exerciseID":"Cable_Crossover","sets":4,"repMin":10,"repMax":15,"restSeconds":90,"coachNote":"x"},
         {"exerciseID":"Lat_Pulldown","sets":4,"repMin":10,"repMax":15,"restSeconds":90,"coachNote":"x"},
         {"exerciseID":"Leg_Extension","sets":4,"repMin":10,"repMax":15,"restSeconds":90,"coachNote":"x"}]}
     ],
     "weeklyVolumeTargets":[{"muscle":"chest","targetSets":12},{"muscle":"back","targetSets":12},{"muscle":"quads","targetSets":12}]}
    """

    @Test func noProviderUsesRuleEngine() async throws {
        let coord = PlanCoordinator(provider: nil, catalog: try catalog())
        let r = await coord.makePlan(context: ctx(), weekStartDate: .init())
        #expect(r.source == .ruleEngine)
        #expect(r.call == nil)
        #expect(r.issues.isEmpty)
    }

    @Test func validAIResponseIsUsed() async throws {
        let stub = StubLLMProvider(responses: [.success(validDTOJSON)])
        let coord = PlanCoordinator(provider: stub, catalog: try catalog())
        let r = await coord.makePlan(context: ctx(), weekStartDate: .init())
        #expect(r.source == .ai)
        #expect(r.issues.isEmpty)
        #expect(r.call?.succeeded == true)
        #expect(stub.callCount == 1)
    }
}
```

> If `validAIResponseIsUsed` fails on `issues.isEmpty` (a `weeklyVolumeOutOfBand` because the hand-written DTO's set counts land outside a band for the stub context) — adjust the DTO's `sets` values in the fixture until it validates. Do not change `PlanCoordinator` or `PlanValidator`.

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Write `PlanCoordinator.swift` (happy path)**

```swift
import Foundation
import FitnessDomain
import ExerciseCatalog
import RuleEngine
import PlanValidation
import LLMKit

nonisolated struct CallOutcome: Sendable, Equatable {
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int
    let succeeded: Bool
}

nonisolated struct CoordinatorResult: Sendable {
    let plan: WeeklyPlan
    let source: PlanSource
    let issues: [ValidationIssue]
    let call: CallOutcome?
}

nonisolated struct PlanCoordinator {
    let provider: (any LLMProvider)?
    let catalog: CatalogStore
    private let prompts: PlanPromptBuilder
    private let ruleBuilder: RulePlanBuilder
    private let validator: PlanValidator

    init(provider: (any LLMProvider)?, catalog: CatalogStore) {
        self.provider = provider
        self.catalog = catalog
        self.prompts = PlanPromptBuilder(catalog: catalog)
        self.ruleBuilder = RulePlanBuilder(catalog: catalog)
        self.validator = PlanValidator(catalog: catalog)
    }

    func makePlan(context: UserContext, weekStartDate: Date) async -> CoordinatorResult {
        guard let provider else {
            return ruleResult(context: context, weekStartDate: weekStartDate,
                              source: .ruleEngine, call: nil)
        }

        do {
            let result = try await provider.complete(
                system: prompts.system(),
                user: prompts.user(context: context),
                schema: WeeklyPlanDTO.planJSONSchema,
                as: WeeklyPlanDTO.self)
            let plan = result.value.toDomain(weekStartDate: weekStartDate, source: .ai)
            let issues = validator.validate(plan, context: context)
            let call = CallOutcome(inputTokens: result.inputTokens,
                                   outputTokens: result.outputTokens,
                                   cachedTokens: result.cachedTokens,
                                   succeeded: issues.isEmpty)
            if issues.isEmpty {
                return CoordinatorResult(plan: plan, source: .ai, issues: [], call: call)
            }
            // retry/fallback added in Task 7
            return ruleResult(context: context, weekStartDate: weekStartDate,
                              source: .fallback, call: call)
        } catch {
            return ruleResult(context: context, weekStartDate: weekStartDate,
                              source: .fallback, call: nil)
        }
    }

    private func ruleResult(context: UserContext, weekStartDate: Date,
                            source: PlanSource, call: CallOutcome?) -> CoordinatorResult {
        var plan = ruleBuilder.build(context: context, weekStartDate: weekStartDate)
        if source == .fallback {
            plan = WeeklyPlan(weekStartDate: plan.weekStartDate, source: .fallback,
                              rationale: plan.rationale, sessions: plan.sessions,
                              weeklyVolumeTargets: plan.weeklyVolumeTargets)
        }
        let issues = validator.validate(plan, context: context)
        return CoordinatorResult(plan: plan, source: source, issues: issues, call: call)
    }
}
```

- [ ] **Step 4: Run — expect PASS.**

- [ ] **Step 5: Commit** — `git commit -m "Add PlanCoordinator happy path and rule-engine fallback"`

---

## Task 7: PlanCoordinator — retry then fallback

**Files:**
- Modify: `AI/PlanCoordinator.swift`
- Modify: `FitnessTrackerTests/PlanCoordinatorTests.swift`

**Interfaces:**
- `makePlan` gains: on first AI response with issues, call **once more** with `prompts.user(context:, priorIssues: issueStrings)`. Re-validate. If clean → `.ai`. Else → rule-engine `.fallback` (carrying the *last* `CallOutcome`). On any thrown error at any point → `.fallback` with `call: nil` (or the last successful call's outcome if one occurred).
- Add `private func describe(_ issues: [ValidationIssue]) -> [String]` — short human strings (`"unknown exercise ID: X"`, `"session 2 has no items"`, `"chest weekly sets 40 outside 8–22"`, etc.).

- [ ] **Step 1: Failing tests** (append)

```swift
@Test func retriesOnceThenAcceptsSecond() async throws {
    let badJSON = """
    {"rationale":"bad","sessions":[{"order":0,"focusMuscles":["chest"],"items":[
      {"exerciseID":"Ghost_Lift","sets":3,"repMin":8,"repMax":12,"restSeconds":150,"coachNote":"x"}]}],
     "weeklyVolumeTargets":[]}
    """
    let stub = StubLLMProvider(responses: [.success(badJSON), .success(validDTOJSON)])
    let coord = PlanCoordinator(provider: stub, catalog: try catalog())
    let r = await coord.makePlan(context: ctx(), weekStartDate: .init())
    #expect(stub.callCount == 2)
    #expect(r.source == .ai)
    #expect(stub.lastUser.localizedCaseInsensitiveContains("previous attempt"))
}

@Test func twoBadResponsesFallBackToRuleEngine() async throws {
    let badJSON = """
    {"rationale":"bad","sessions":[{"order":0,"focusMuscles":["chest"],"items":[
      {"exerciseID":"Ghost_Lift","sets":3,"repMin":8,"repMax":12,"restSeconds":150,"coachNote":"x"}]}],
     "weeklyVolumeTargets":[]}
    """
    let stub = StubLLMProvider(responses: [.success(badJSON), .success(badJSON)])
    let coord = PlanCoordinator(provider: stub, catalog: try catalog())
    let r = await coord.makePlan(context: ctx(), weekStartDate: .init())
    #expect(stub.callCount == 2)
    #expect(r.source == .fallback)
    #expect(r.issues.isEmpty)                 // the rule-engine plan itself validates
    #expect(r.call?.succeeded == false)
}

@Test func thrownErrorFallsBack() async throws {
    let stub = StubLLMProvider(responses: [.failure(.rateLimited)])
    let coord = PlanCoordinator(provider: stub, catalog: try catalog())
    let r = await coord.makePlan(context: ctx(), weekStartDate: .init())
    #expect(r.source == .fallback)
    #expect(stub.callCount == 1)
}
```

- [ ] **Step 2: Run — expect FAIL** (`retriesOnceThenAcceptsSecond` and `twoBadResponsesFallBackToRuleEngine`).

- [ ] **Step 3: Update `makePlan`** — replace the "retry/fallback added in Task 7" branch:

```swift
        // one retry with the validation errors fed back
        let retryUser = prompts.user(context: context, priorIssues: describe(issues))
        do {
            let retry = try await provider.complete(
                system: prompts.system(), user: retryUser,
                schema: WeeklyPlanDTO.planJSONSchema, as: WeeklyPlanDTO.self)
            let retryPlan = retry.value.toDomain(weekStartDate: weekStartDate, source: .ai)
            let retryIssues = validator.validate(retryPlan, context: context)
            let retryCall = CallOutcome(inputTokens: retry.inputTokens,
                                        outputTokens: retry.outputTokens,
                                        cachedTokens: retry.cachedTokens,
                                        succeeded: retryIssues.isEmpty)
            if retryIssues.isEmpty {
                return CoordinatorResult(plan: retryPlan, source: .ai, issues: [], call: retryCall)
            }
            return ruleResult(context: context, weekStartDate: weekStartDate,
                              source: .fallback, call: retryCall)
        } catch {
            return ruleResult(context: context, weekStartDate: weekStartDate,
                              source: .fallback, call: call)
        }
```

And add:

```swift
    private func describe(_ issues: [ValidationIssue]) -> [String] {
        issues.map { issue in
            switch issue {
            case .unknownExerciseID(let id): "unknown exercise ID: \(id)"
            case .excludedExercisePresent(let id): "used an excluded exercise: \(id)"
            case .excludedMusclePresent(let m): "trained an excluded muscle: \(m.rawValue)"
            case .weeklyVolumeOutOfBand(let m, let sets, let band):
                "\(m.rawValue) weekly sets \(sets) outside \(band.mev)–\(band.mrv)"
            case .emptySession(let order): "session \(order + 1) has no items"
            }
        }
    }
```

- [ ] **Step 4: Run — expect PASS** (all `PlanCoordinatorTests`).

- [ ] **Step 5: Commit** — `git commit -m "Add PlanCoordinator retry-then-fallback"`

---

## Task 8: OpenAICompatibleProvider

**Files:**
- Create: `AI/Adapters/OpenAICompatibleProvider.swift`
- Test: `FitnessTrackerTests/OpenAICompatibleProviderTests.swift`

**Interfaces:**
- Produces `nonisolated struct OpenAICompatibleProvider: LLMProvider`:
  - `init(baseURL: URL, apiKey: String?, modelID: String, session: URLSession = .shared)`
  - `complete`: POST `baseURL.appending(path: "chat/completions")`, JSON body `{ model, messages:[{role:system,content},{role:user,content}], response_format:{ type:"json_schema", json_schema:{ name:"plan", strict:true, schema:<parsed schema> } } }`, header `Authorization: Bearer <key>` when key present. Decode: HTTP≠2xx → `LLMError.transport("HTTP \(code): \(body prefix)")`; parse `{ choices:[{ message:{ content } }], usage:{ prompt_tokens, completion_tokens, prompt_tokens_details:{ cached_tokens } } }`; `content` (a JSON string) → decode `Value`; on decode failure → `LLMError.decoding(...)`. Missing choices → `LLMError.emptyResponse`.
  - `completeWithImage`: for 1c, `throw LLMError.visionUnsupported` (real multimodal is a follow-up).

- [ ] **Step 1: Failing test**

```swift
import Testing
import Foundation
import LLMKit
@testable import FitnessTracker

struct OpenAICompatibleProviderTests {
    private struct Dummy: Codable, Sendable, Equatable { let ok: Bool }

    @Test func parsesContentAndUsage() async throws {
        StubURLProtocol.handler = { req in
            #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
            let body = """
            {"choices":[{"message":{"content":"{\\"ok\\":true}"}}],
             "usage":{"prompt_tokens":11,"completion_tokens":22,"prompt_tokens_details":{"cached_tokens":3}}}
            """
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(body.utf8))
        }
        defer { StubURLProtocol.handler = nil }

        let p = OpenAICompatibleProvider(baseURL: URL(string: "https://api.example.com/v1")!,
                                         apiKey: "sk-test", modelID: "gpt-x",
                                         session: StubURLProtocol.session())
        let r: LLMResult<Dummy> = try await p.complete(system: "s", user: "u",
                                                       schema: JSONSchema(json: "{}"), as: Dummy.self)
        #expect(r.value == Dummy(ok: true))
        #expect(r.inputTokens == 11)
        #expect(r.outputTokens == 22)
        #expect(r.cachedTokens == 3)
    }

    @Test func httpErrorBecomesTransportError() async {
        StubURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!,
             Data(#"{"error":"slow down"}"#.utf8))
        }
        defer { StubURLProtocol.handler = nil }
        let p = OpenAICompatibleProvider(baseURL: URL(string: "https://x/v1")!, apiKey: nil,
                                         modelID: "m", session: StubURLProtocol.session())
        await #expect(throws: LLMError.self) {
            let _: LLMResult<Dummy> = try await p.complete(system: "s", user: "u",
                schema: JSONSchema(json: "{}"), as: Dummy.self)
        }
    }
}
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Write `OpenAICompatibleProvider.swift`**

```swift
import Foundation
import LLMKit

nonisolated struct OpenAICompatibleProvider: LLMProvider {
    let baseURL: URL
    let apiKey: String?
    let modelID: String
    let session: URLSession

    init(baseURL: URL, apiKey: String?, modelID: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelID = modelID
        self.session = session
    }

    func complete<Value: Decodable & Sendable>(system: String, user: String,
                                               schema: JSONSchema,
                                               as type: Value.Type) async throws -> LLMResult<Value> {
        var request = URLRequest(url: baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }

        let schemaObject = try JSONSerialization.jsonObject(with: Data(schema.json.utf8))
        let body: [String: Any] = [
            "model": modelID,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": ["name": "plan", "strict": true, "schema": schemaObject],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LLMError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw LLMError.transport("no HTTP response") }
        guard (200...299).contains(http.statusCode) else {
            throw LLMError.transport("HTTP \(http.statusCode): \(String(decoding: data.prefix(300), as: UTF8.self))")
        }

        struct Envelope: Decodable {
            struct Choice: Decodable { struct Message: Decodable { let content: String }; let message: Message }
            struct Usage: Decodable {
                struct Details: Decodable { let cached_tokens: Int? }
                let prompt_tokens: Int?
                let completion_tokens: Int?
                let prompt_tokens_details: Details?
            }
            let choices: [Choice]
            let usage: Usage?
        }
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
        catch { throw LLMError.decoding("envelope: \(error)") }
        guard let content = envelope.choices.first?.message.content else { throw LLMError.emptyResponse }

        let value: Value
        do { value = try JSONDecoder().decode(Value.self, from: Data(content.utf8)) }
        catch { throw LLMError.decoding("content: \(error)") }

        return LLMResult(value: value,
                         inputTokens: envelope.usage?.prompt_tokens ?? 0,
                         outputTokens: envelope.usage?.completion_tokens ?? 0,
                         cachedTokens: envelope.usage?.prompt_tokens_details?.cached_tokens ?? 0,
                         rawJSON: content)
    }

    func completeWithImage<Value: Decodable & Sendable>(system: String, user: String,
                                                        image: ImagePayload, schema: JSONSchema,
                                                        as type: Value.Type) async throws -> LLMResult<Value> {
        throw LLMError.visionUnsupported
    }
}
```

- [ ] **Step 4: Run — expect PASS.**

- [ ] **Step 5: Commit** — `git commit -m "Add OpenAICompatibleProvider adapter"`

---

## Task 9: GeminiProvider (AI Studio)

**Files:**
- Create: `AI/Adapters/GeminiProvider.swift`
- Test: `FitnessTrackerTests/GeminiProviderTests.swift`

**Interfaces:**
- Produces `nonisolated struct GeminiProvider: LLMProvider`:
  - `init(apiKey: String, modelID: String, session: URLSession = .shared, baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta/")!)`
  - `complete`: POST `baseURL.appending(path: "models/\(modelID):generateContent")`, header `x-goog-api-key: <key>`, body `{ system_instruction:{ parts:[{text:system}] }, contents:[{ role:"user", parts:[{text:user}] }], generationConfig:{ responseMimeType:"application/json", responseSchema:<parsed schema> } }`. HTTP≠2xx → `LLMError.transport`. Parse `{ candidates:[{ content:{ parts:[{ text }] } }], usageMetadata:{ promptTokenCount, candidatesTokenCount, cachedContentTokenCount } }`; `text` → decode `Value`.
  - `completeWithImage`: `throw LLMError.visionUnsupported` for 1c.

- [ ] **Step 1: Failing test** (mirror Task 8's shape with a Gemini envelope):

```swift
import Testing
import Foundation
import LLMKit
@testable import FitnessTracker

struct GeminiProviderTests {
    private struct Dummy: Codable, Sendable, Equatable { let ok: Bool }

    @Test func parsesTextAndUsageMetadata() async throws {
        StubURLProtocol.handler = { req in
            #expect(req.value(forHTTPHeaderField: "x-goog-api-key") == "g-key")
            #expect(req.url?.absoluteString.contains("models/gemini-x:generateContent") == true)
            let body = """
            {"candidates":[{"content":{"parts":[{"text":"{\\"ok\\":true}"}]}}],
             "usageMetadata":{"promptTokenCount":7,"candidatesTokenCount":9,"cachedContentTokenCount":2}}
            """
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(body.utf8))
        }
        defer { StubURLProtocol.handler = nil }

        let p = GeminiProvider(apiKey: "g-key", modelID: "gemini-x", session: StubURLProtocol.session())
        let r: LLMResult<Dummy> = try await p.complete(system: "s", user: "u",
                                                       schema: JSONSchema(json: "{}"), as: Dummy.self)
        #expect(r.value == Dummy(ok: true))
        #expect(r.inputTokens == 7)
        #expect(r.outputTokens == 9)
        #expect(r.cachedTokens == 2)
    }
}
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Write `GeminiProvider.swift`** — same structure as Task 8, Gemini body + envelope:

```swift
import Foundation
import LLMKit

nonisolated struct GeminiProvider: LLMProvider {
    let apiKey: String
    let modelID: String
    let session: URLSession
    let baseURL: URL

    init(apiKey: String, modelID: String, session: URLSession = .shared,
         baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta/")!) {
        self.apiKey = apiKey
        self.modelID = modelID
        self.session = session
        self.baseURL = baseURL
    }

    func complete<Value: Decodable & Sendable>(system: String, user: String,
                                               schema: JSONSchema,
                                               as type: Value.Type) async throws -> LLMResult<Value> {
        var request = URLRequest(url: baseURL.appending(path: "models/\(modelID):generateContent"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let schemaObject = try JSONSerialization.jsonObject(with: Data(schema.json.utf8))
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": [["text": user]]]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": schemaObject,
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) }
        catch { throw LLMError.transport(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw LLMError.transport("no HTTP response") }
        guard (200...299).contains(http.statusCode) else {
            throw LLMError.transport("HTTP \(http.statusCode): \(String(decoding: data.prefix(300), as: UTF8.self))")
        }

        struct Envelope: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable { struct Part: Decodable { let text: String }; let parts: [Part] }
                let content: Content
            }
            struct Usage: Decodable {
                let promptTokenCount: Int?
                let candidatesTokenCount: Int?
                let cachedContentTokenCount: Int?
            }
            let candidates: [Candidate]
            let usageMetadata: Usage?
        }
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
        catch { throw LLMError.decoding("envelope: \(error)") }
        guard let text = envelope.candidates.first?.content.parts.first?.text else {
            throw LLMError.emptyResponse
        }
        let value: Value
        do { value = try JSONDecoder().decode(Value.self, from: Data(text.utf8)) }
        catch { throw LLMError.decoding("text: \(error)") }

        return LLMResult(value: value,
                         inputTokens: envelope.usageMetadata?.promptTokenCount ?? 0,
                         outputTokens: envelope.usageMetadata?.candidatesTokenCount ?? 0,
                         cachedTokens: envelope.usageMetadata?.cachedContentTokenCount ?? 0,
                         rawJSON: text)
    }

    func completeWithImage<Value: Decodable & Sendable>(system: String, user: String,
                                                        image: ImagePayload, schema: JSONSchema,
                                                        as type: Value.Type) async throws -> LLMResult<Value> {
        throw LLMError.visionUnsupported
    }
}
```

- [ ] **Step 4: Run — expect PASS.**

- [ ] **Step 5: Commit** — `git commit -m "Add GeminiProvider adapter (AI Studio)"`

---

## Task 10: FoundationModelsProvider (on-device)

**Files:**
- Create: `AI/Adapters/FoundationModelsProvider.swift`
- Test: `FitnessTrackerTests/FoundationModelsProviderTests.swift`

**Interfaces:**
- Produces `nonisolated struct FoundationModelsProvider: LLMProvider`:
  - `init()` — no config; uses the system model.
  - Whole file wrapped `#if canImport(FoundationModels)`; provide an `#else` stub whose `complete` throws `LLMError.transport("FoundationModels unavailable")` so the app still builds on machines without it.
  - `complete`: build a single prompt string = `system + "\n\n" + user + "\n\nRespond with JSON only."`; use `LanguageModelSession()` and `session.respond(to: prompt)`; take `.content` (a String), decode `Value` from it (strip a leading/trailing code fence if present). Tokens unknown → `inputTokens: 0, outputTokens: 0, cachedTokens: 0`. If the model is unavailable at runtime (`SystemLanguageModel.default.availability != .available`) → throw `LLMError.transport("on-device model unavailable: <reason>")`.
  - `completeWithImage`: `throw LLMError.visionUnsupported`.

- [ ] **Step 1: Failing/ाguarded test**

```swift
import Testing
import Foundation
import LLMKit
@testable import FitnessTracker

struct FoundationModelsProviderTests {
    private struct Dummy: Codable, Sendable, Equatable { let ok: Bool }

    @Test func returnsDecodedJSONOrThrowsWhenUnavailable() async throws {
        let p = FoundationModelsProvider()
        do {
            let r: LLMResult<Dummy> = try await p.complete(
                system: "You are a test.",
                user: #"Return exactly this JSON: {"ok": true}"#,
                schema: JSONSchema(json: "{}"), as: Dummy.self)
            #expect(r.value == Dummy(ok: true))
        } catch let e as LLMError {
            // Acceptable in CI / a simulator without the model downloaded.
            #expect(e == .visionUnsupported || { if case .transport = e { return true } else { return false } }())
        }
    }
}
```

- [ ] **Step 2: Run** — passes either way (decoded result OR a transport error when the model isn't present).

- [ ] **Step 3: Write `FoundationModelsProvider.swift`**

```swift
import Foundation
import LLMKit

#if canImport(FoundationModels)
import FoundationModels

nonisolated struct FoundationModelsProvider: LLMProvider {
    func complete<Value: Decodable & Sendable>(system: String, user: String,
                                               schema: JSONSchema,
                                               as type: Value.Type) async throws -> LLMResult<Value> {
        guard case .available = SystemLanguageModel.default.availability else {
            throw LLMError.transport("on-device model unavailable")
        }
        let session = LanguageModelSession(instructions: system)
        let prompt = user + "\n\nRespond with a single JSON object only."
        let response: String
        do {
            response = try await session.respond(to: prompt).content
        } catch {
            throw LLMError.transport("FoundationModels: \(error.localizedDescription)")
        }
        let cleaned = Self.stripFences(response)
        let value: Value
        do { value = try JSONDecoder().decode(Value.self, from: Data(cleaned.utf8)) }
        catch { throw LLMError.decoding("on-device content: \(error)") }
        return LLMResult(value: value, inputTokens: 0, outputTokens: 0, cachedTokens: 0, rawJSON: cleaned)
    }

    func completeWithImage<Value: Decodable & Sendable>(system: String, user: String,
                                                        image: ImagePayload, schema: JSONSchema,
                                                        as type: Value.Type) async throws -> LLMResult<Value> {
        throw LLMError.visionUnsupported
    }

    private static func stripFences(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = t.drop(while: { $0 != "\n" }).description
            if t.hasSuffix("```") { t = String(t.dropLast(3)) }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#else

nonisolated struct FoundationModelsProvider: LLMProvider {
    func complete<Value: Decodable & Sendable>(system: String, user: String,
                                               schema: JSONSchema,
                                               as type: Value.Type) async throws -> LLMResult<Value> {
        throw LLMError.transport("FoundationModels unavailable in this build")
    }
    func completeWithImage<Value: Decodable & Sendable>(system: String, user: String,
                                                        image: ImagePayload, schema: JSONSchema,
                                                        as type: Value.Type) async throws -> LLMResult<Value> {
        throw LLMError.visionUnsupported
    }
}
#endif
```

> If the `FoundationModels` API names differ in this SDK (`LanguageModelSession` / `SystemLanguageModel.default.availability` / `.respond(to:)`), fix them against Xcode's autocomplete — the *shape* (session → respond → String content) is stable. Note any change in the task report.

- [ ] **Step 4: Run — expect PASS.**

- [ ] **Step 5: Commit** — `git commit -m "Add FoundationModelsProvider on-device adapter"`

---

## Task 11: LLMProviderFactory

**Files:**
- Create: `AI/LLMProviderFactory.swift`
- Test: `FitnessTrackerTests/LLMProviderFactoryTests.swift`

**Interfaces:**
- Produces `nonisolated enum LLMProviderFactory`:
  - `enum FactoryError: Error, Equatable { case missingBaseURL, missingAPIKey, invalidBaseURL }`
  - `static func make(kind: AdapterKind, baseURL: String?, apiKey: String?, modelID: String, session: URLSession = .shared) throws -> any LLMProvider`
    - `.openAICompatible`: require `baseURL` (→ `URL`, else `.invalidBaseURL`); `apiKey` optional → `OpenAICompatibleProvider`
    - `.gemini`: require `apiKey` (`.missingAPIKey`) → `GeminiProvider`
    - `.appleOnDevice`: → `FoundationModelsProvider()`
  - `static func make(from profile: ProviderProfile, session: URLSession = .shared) throws -> any LLMProvider` — reads the key from `KeychainStore.get(account: profile.apiKeyRef ?? "")` and forwards. (`@MainActor` boundary: this reads `profile` properties — see note.)

> **Isolation note:** `ProviderProfile` is a `@Model` → `@MainActor`. So `make(from:)` is `@MainActor`; it extracts plain `String?`s and calls the `nonisolated` `make(kind:...)`. Callers already on the main actor (the coordinator wiring in Task 15) invoke `make(from:)` before hopping off-actor for the async `makePlan`.

- [ ] **Step 1: Failing test**

```swift
import Testing
import Foundation
import LLMKit
@testable import FitnessTracker

struct LLMProviderFactoryTests {
    @Test func buildsEachKind() throws {
        let oai = try LLMProviderFactory.make(kind: .openAICompatible,
            baseURL: "https://api.example.com/v1", apiKey: "k", modelID: "m")
        #expect(oai is OpenAICompatibleProvider)

        let gem = try LLMProviderFactory.make(kind: .gemini, baseURL: nil, apiKey: "k", modelID: "m")
        #expect(gem is GeminiProvider)

        let od = try LLMProviderFactory.make(kind: .appleOnDevice, baseURL: nil, apiKey: nil, modelID: "")
        #expect(od is FoundationModelsProvider)
    }

    @Test func missingConfigThrows() {
        #expect(throws: LLMProviderFactory.FactoryError.invalidBaseURL) {
            _ = try LLMProviderFactory.make(kind: .openAICompatible, baseURL: nil, apiKey: nil, modelID: "m")
        }
        #expect(throws: LLMProviderFactory.FactoryError.missingAPIKey) {
            _ = try LLMProviderFactory.make(kind: .gemini, baseURL: nil, apiKey: nil, modelID: "m")
        }
    }
}
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Write `LLMProviderFactory.swift`**

```swift
import Foundation
import LLMKit

nonisolated enum LLMProviderFactory {
    enum FactoryError: Error, Equatable {
        case missingBaseURL, missingAPIKey, invalidBaseURL
    }

    static func make(kind: AdapterKind, baseURL: String?, apiKey: String?,
                     modelID: String, session: URLSession = .shared) throws -> any LLMProvider {
        switch kind {
        case .openAICompatible:
            guard let baseURL, let url = URL(string: baseURL) else { throw FactoryError.invalidBaseURL }
            return OpenAICompatibleProvider(baseURL: url, apiKey: apiKey, modelID: modelID, session: session)
        case .gemini:
            guard let apiKey, !apiKey.isEmpty else { throw FactoryError.missingAPIKey }
            return GeminiProvider(apiKey: apiKey, modelID: modelID, session: session)
        case .appleOnDevice:
            return FoundationModelsProvider()
        }
    }

    @MainActor
    static func make(from profile: ProviderProfile, session: URLSession = .shared) throws -> any LLMProvider {
        let key = profile.apiKeyRef.flatMap { try? KeychainStore.get(account: $0) } ?? nil
        return try make(kind: profile.adapterKind, baseURL: profile.baseURL,
                        apiKey: key, modelID: profile.modelID, session: session)
    }
}
```

- [ ] **Step 4: Run — expect PASS.**

- [ ] **Step 5: Commit** — `git commit -m "Add LLMProviderFactory"`

---

## Task 12: AICallRecord model + cost math

**Files:**
- Create: `Models/AICallRecord.swift`
- Modify: `FitnessTrackerApp.swift` (add `AICallRecord.self` to the container)
- Test: `FitnessTrackerTests/AICallRecordTests.swift`

**Interfaces:**
- Produces `@Model final class AICallRecord`:
  - `timestamp: Date`, `callType: String`, `providerDisplayName: String`, `modelID: String`, `inputTokens: Int`, `outputTokens: Int`, `cachedTokens: Int`, `costUSD: Double`, `success: Bool`, `usedFallback: Bool`
  - `init(...)` with all fields; `timestamp = .now`
  - `nonisolated static func cost(inputTokens: Int, outputTokens: Int, cachedTokens: Int, pricePerMTokIn: Double, pricePerMTokOut: Double, pricePerMTokCached: Double) -> Double` — `(Double(inputTokens)/1_000_000)*in + (out/1e6)*out + (cached/1e6)*cached`, rounded to 6 dp.

- [ ] **Step 1: Failing test**

```swift
import Testing
import Foundation
import SwiftData
@testable import FitnessTracker

@MainActor
struct AICallRecordTests {
    @Test func costMath() {
        let c = AICallRecord.cost(inputTokens: 500_000, outputTokens: 100_000, cachedTokens: 0,
                                  pricePerMTokIn: 0.30, pricePerMTokOut: 2.50, pricePerMTokCached: 0)
        #expect(abs(c - (0.15 + 0.25)) < 1e-9)
    }

    @Test func persists() throws {
        let container = try ModelContainer(for: AICallRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let r = AICallRecord(callType: "weeklyPlan", providerDisplayName: "P", modelID: "m",
                             inputTokens: 10, outputTokens: 20, cachedTokens: 0,
                             costUSD: 0.0001, success: true, usedFallback: false)
        container.mainContext.insert(r)
        try container.mainContext.save()
        #expect(try container.mainContext.fetch(FetchDescriptor<AICallRecord>()).count == 1)
    }
}
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Write `AICallRecord.swift`**

```swift
import Foundation
import SwiftData

@Model
final class AICallRecord {
    var timestamp: Date
    var callType: String
    var providerDisplayName: String
    var modelID: String
    var inputTokens: Int
    var outputTokens: Int
    var cachedTokens: Int
    var costUSD: Double
    var success: Bool
    var usedFallback: Bool

    init(callType: String, providerDisplayName: String, modelID: String,
         inputTokens: Int, outputTokens: Int, cachedTokens: Int,
         costUSD: Double, success: Bool, usedFallback: Bool) {
        self.timestamp = .now
        self.callType = callType
        self.providerDisplayName = providerDisplayName
        self.modelID = modelID
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.costUSD = costUSD
        self.success = success
        self.usedFallback = usedFallback
    }

    nonisolated static func cost(inputTokens: Int, outputTokens: Int, cachedTokens: Int,
                                 pricePerMTokIn: Double, pricePerMTokOut: Double,
                                 pricePerMTokCached: Double) -> Double {
        let raw = Double(inputTokens) / 1_000_000 * pricePerMTokIn
            + Double(outputTokens) / 1_000_000 * pricePerMTokOut
            + Double(cachedTokens) / 1_000_000 * pricePerMTokCached
        return (raw * 1_000_000).rounded() / 1_000_000
    }
}
```

- [ ] **Step 4: `FitnessTrackerApp.swift`** — container is now `[UserProfile.self, StoredPlan.self, ProviderProfile.self, AICallRecord.self]`.

- [ ] **Step 5: Run — expect PASS.**

- [ ] **Step 6: Commit** — `git commit -m "Add AICallRecord model and cost math"`

---

## Task 13: CostSummary aggregation

**Files:**
- Create: `AI/CostSummary.swift`
- Test: `FitnessTrackerTests/CostSummaryTests.swift`

**Interfaces:**
- Produces `nonisolated struct CostSummary: Sendable, Equatable`:
  - `let monthToDateUSD: Double`, `let allTimeUSD: Double`, `let callCount: Int`
  - `nonisolated static func from(records: [AICallRecordSnapshot], now: Date) -> CostSummary`
  - `struct AICallRecordSnapshot: Sendable { let timestamp: Date; let costUSD: Double }` — plain value so the aggregation stays off the `@MainActor` model. (`@MainActor` callers map `[AICallRecord]` → `[AICallRecordSnapshot]` first.)
  - "month to date" = records whose `timestamp` is in the same calendar month & year as `now` (use `Calendar.current`).

- [ ] **Step 1: Failing test**

```swift
import Testing
import Foundation
@testable import FitnessTracker

struct CostSummaryTests {
    @Test func splitsMonthToDateFromAllTime() {
        let cal = Calendar.current
        let now = Date()
        let thisMonth = now
        let lastMonth = cal.date(byAdding: .month, value: -1, to: now)!

        let snaps = [
            CostSummary.AICallRecordSnapshot(timestamp: thisMonth, costUSD: 0.10),
            CostSummary.AICallRecordSnapshot(timestamp: thisMonth, costUSD: 0.05),
            CostSummary.AICallRecordSnapshot(timestamp: lastMonth, costUSD: 1.00),
        ]
        let s = CostSummary.from(records: snaps, now: now)
        #expect(abs(s.monthToDateUSD - 0.15) < 1e-9)
        #expect(abs(s.allTimeUSD - 1.15) < 1e-9)
        #expect(s.callCount == 3)
    }
}
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Write `CostSummary.swift`**

```swift
import Foundation

nonisolated struct CostSummary: Sendable, Equatable {
    struct AICallRecordSnapshot: Sendable, Equatable {
        let timestamp: Date
        let costUSD: Double
    }

    let monthToDateUSD: Double
    let allTimeUSD: Double
    let callCount: Int

    static func from(records: [AICallRecordSnapshot], now: Date) -> CostSummary {
        let cal = Calendar.current
        let nowComps = cal.dateComponents([.year, .month], from: now)
        var mtd = 0.0
        var all = 0.0
        for r in records {
            all += r.costUSD
            let c = cal.dateComponents([.year, .month], from: r.timestamp)
            if c.year == nowComps.year && c.month == nowComps.month { mtd += r.costUSD }
        }
        return CostSummary(monthToDateUSD: mtd, allTimeUSD: all, callCount: records.count)
    }
}
```

- [ ] **Step 4: Run — expect PASS.**

- [ ] **Step 5: Commit** — `git commit -m "Add CostSummary aggregation"`

---

## Task 14: Route plan generation through PlanCoordinator

**Files:**
- Modify: `RootView.swift`
- Modify: `Features/Settings/SettingsView.swift`
- Delete: `Planning/PlanService.swift` and `FitnessTrackerTests/PlanServiceTests.swift` (superseded by `PlanCoordinator`; the coordinator's no-provider path is the old behaviour)

**Interfaces:**
- `RootView` and `SettingsView` gain a shared helper (put it in a new `AI/PlanGeneration.swift`):
  - `@MainActor func generateAndStore(context: UserContext, activeProfile: ProviderProfile?, catalog: CatalogStore, modelContext: ModelContext) async` —
    1. build `provider = activeProfile.flatMap { try? LLMProviderFactory.make(from: $0) }`
    2. `let result = await PlanCoordinator(provider: provider, catalog: catalog).makePlan(context: context, weekStartDate: .now)`
    3. insert `StoredPlan(plan: result.plan, hadValidationIssues: !result.issues.isEmpty)`
    4. if `result.call != nil` **or** `provider != nil`: compute cost from `activeProfile` prices, insert `AICallRecord(... usedFallback: result.source == .fallback, success: result.source == .ai ...)`
    5. `try? modelContext.save()`
- Both call sites become `async` (wrap in a `Task { await ... }` from the button / `onComplete`).

- [ ] **Step 1: Write `AI/PlanGeneration.swift`** — the `generateAndStore` helper per the interface above (full code; ~35 lines).

- [ ] **Step 2: Update `RootView.regeneratePlan`** — take the active profile from a new `@Query(filter: #Predicate<ProviderProfile> { $0.isActive })` (or fetch first active), call `Task { await generateAndStore(...) }`.

- [ ] **Step 3: Update `SettingsView.regenerate`** — same.

- [ ] **Step 4: Delete `PlanService.swift` + `PlanServiceTests.swift`.** Update any other reference (there should be none outside these two files and the deleted test).

- [ ] **Step 5: Run all unit tests** — expect green (minus the deleted `PlanServiceTests`; `PlanCoordinatorTests` covers the path).

- [ ] **Step 6: Build the app** (`xcodebuild build ...`) — expect success.

- [ ] **Step 7: Commit** — `git commit -m "Route plan generation through PlanCoordinator"`

---

## Task 15: Provider profile UI (Settings)

**Files:**
- Create: `Features/Settings/ProviderProfileListView.swift`
- Create: `Features/Settings/ProviderProfileEditView.swift`
- Modify: `Features/Settings/SettingsView.swift`

**Interfaces / behaviour:**
- `SettingsView` "AI Coach" section (currently disabled) becomes: a `NavigationLink("Providers")` → `ProviderProfileListView`, and a line showing the active profile's `displayName` or "None (rule engine)".
- `ProviderProfileListView`: `@Query` all `ProviderProfile`; each row shows `displayName` + `adapterKind` + a checkmark if `isActive`; tap a row → `ProviderProfileEditView`; swipe to delete (also clears its Keychain entry via `apiKeyRef`); toolbar `+` → new `ProviderProfileEditView`.
- `ProviderProfileEditView(profile: ProviderProfile?)`: a `Form` with `displayName`, `adapterKind` Picker (`AdapterKind.allCases`), `modelID`, `baseURL` (shown only for `.openAICompatible`), `SecureField` "API key" (shown for `.openAICompatible` optional / `.gemini` required; hidden for `.appleOnDevice`), price fields (`pricePerMTokIn/Out/Cached`, `.number`), `supportsVision` toggle. Save:
  - new: create `ProviderProfile`, `context.insert`
  - existing: mutate fields
  - if the key field is non-empty: `let ref = profile.apiKeyRef ?? UUID().uuidString; try? KeychainStore.set(key, account: ref); profile.apiKeyRef = ref`
  - "Set as active" button: set this `isActive = true` and every other profile `isActive = false`; `save()`.
- Seed helper (call once from `SettingsView.task` if `profiles.isEmpty` is **not** required — do **not** auto-seed; the user adds their first profile). Provide a "Add on-device (free)" quick action in the list toolbar that inserts a ready `.appleOnDevice` profile named "On-device (Apple)".

**Verification: SwiftUI + you run it.** Acceptance = build succeeds; in the simulator you can add an on-device profile, set it active, and Settings shows it as active.

- [ ] **Step 1: Write `ProviderProfileEditView.swift`** (full `Form`, per the interface).
- [ ] **Step 2: Write `ProviderProfileListView.swift`** (list + `+` + "Add on-device" + delete).
- [ ] **Step 3: Update `SettingsView.swift`** — replace the disabled "AI Coach" section with the `NavigationLink` + active-profile line.
- [ ] **Step 4: Build (`⌘B`).** Fix compile errors.
- [ ] **Step 5: Manual check** — run, Settings → Providers → "Add on-device" → set active → back → Settings shows "Active: On-device (Apple)". Report what each screen showed.
- [ ] **Step 6: Commit** — `git commit -m "Add provider profile management UI"`

---

## Task 16: Cost UI

**Files:**
- Modify: `Features/Plan/PlanView.swift`
- Modify: `Features/Settings/SettingsView.swift`
- Create: `Features/Plan/CostChip.swift`

**Interfaces / behaviour:**
- `CostChip(summary: CostSummary)` — a small capsule: `"$\(summary.monthToDateUSD, format: .currency(code: "USD")) this month"` (or "$0.00 this month"). Tappable → nothing in 1c (or navigates to Settings).
- `PlanView` gains `let costSummary: CostSummary` and shows `CostChip` in the toolbar (`.topBarLeading`). `RootView` computes it: `@Query(sort: \AICallRecord.timestamp) private var calls: [AICallRecord]` → map to snapshots → `CostSummary.from(records:now:)` → pass in.
- `SettingsView` gains a "Usage" section: `LabeledContent("This month", value: ...)`, `LabeledContent("All time", value: ...)`, `LabeledContent("AI calls", value: "\(summary.callCount)")`.
- After a generation (`generateAndStore`), set a `@State private var lastNote: String?` on the calling view: `"Coach updated"` / `"Used the rule-engine backup"` / `"Coach updated · ~$\(cost)"`. Show it as a brief `.overlay` banner or a `.toast`-style `Text` that clears after 3s (a simple `.task` sleep). Keep it minimal.

**Verification: SwiftUI + you run it.** Acceptance = build succeeds; the plan screen shows a "$0.00 this month" chip; after a generation with an active on-device profile the chip still shows $0.00 (on-device is free) and the note appears.

- [ ] **Step 1: Write `CostChip.swift`.**
- [ ] **Step 2: Wire `PlanView` + `RootView` (compute summary) + `SettingsView` Usage section + the post-generation note.**
- [ ] **Step 3: Build (`⌘B`).**
- [ ] **Step 4: Manual check** — run; plan screen has the chip; Settings has Usage. Report.
- [ ] **Step 5: Commit** — `git commit -m "Add real-time cost UI (chip + usage + note)"`

---

## Task 17: Acceptance pass + docs

**Files:**
- Modify: `FitnessTracker/README.md`
- Modify: `docs/HANDOFF.md`, `docs/04-roadmap-phases.md`

- [ ] **Step 1: Full test run** — `xcodebuild test -scheme FitnessTracker -only-testing:FitnessTrackerTests` all green; `cd FitnessCore && swift test` still 35/35.

- [ ] **Step 2: Simulator acceptance** — clean install. (a) Skip providers → onboarding → plan appears, `source` = rule engine, chip $0.00. (b) Settings → Providers → "Add on-device" → active → Regenerate → plan appears (source `ai` if the on-device model is present, else `fallback`), note shows. (c) Add an `openAICompatible` profile pointing at a real endpoint with a real key **only if you have one** — otherwise note that path is code-verified by `OpenAICompatibleProviderTests`. (d) Start over still works.

- [ ] **Step 3: Update `FitnessTracker/README.md`** — "Phase 1c" section: provider profiles, the 3 adapters + deferred ones, `PlanCoordinator` flow, cost ledger. Move the AI items out of "Not yet".

- [ ] **Step 4: Update `docs/HANDOFF.md`** (§2 status → "Phase 1c complete", next → Phase 2 "Run my session"; chronology entry; bump date) and `docs/04-roadmap-phases.md` (mark 1c ✅).

- [ ] **Step 5: Commit** — `git commit -m "Phase 1c acceptance pass and docs"`

---

## Self-Review

**1. Spec coverage:**

| Spec item | Task |
|-----------|------|
| `docs/03` §3 `ProviderProfile` (adapterKind, baseURL, key ref, modelID, prices, vision, active) | 1 |
| `docs/03` §3 `AICallRecord` (per-call ledger, cost frozen) | 12 |
| `docs/03` §6 four `adapterKind`s / `LLMProvider` adapters | 8, 9, 10 (+ native Anthropic/Bedrock/Vertex deferred, documented) |
| `docs/03` §6 provider+model as runtime config, no app update | 1, 11, 15 |
| `docs/03` §6 native structured output per provider | 8 (`json_schema`), 9 (`responseSchema`), 10 (`@Generable`/JSON prompt) |
| `docs/03` §6 InBody vision routing | **deferred** — `completeWithImage` throws `.visionUnsupported` in every adapter; real vision is Phase 4 (InBody) |
| `docs/03` §7 validation on every AI response → retry once → rule fallback | 6, 7 |
| `docs/03` §6.1 weekly-plan request payload (profile, equipment, catalog slice, landmarks, schema) | 4 |
| `docs/02` §9.1 user-managed provider profiles + switch | 1, 15 |
| `docs/02` §9.2 real-time cost: `$` chip, per-generation note, Settings usage | 13, 16 |
| `docs/02` §9.3 budget cap + "pause AI" toggle | **deferred to a 1c follow-up** — noted below |
| `docs/06` A11–A13 | 1, 12, 13, 16 (budget: partial — see gaps) |
| BYO key in Keychain | 2, 11, 15 |

**Gaps / intentional deferrals (documented):**
- **Budget cap + `pauseAIWhenOverBudget` toggle** (`docs/02` §9.3, `docs/06` A13) — the cost *ledger and display* ship in 1c; the enforced monthly cap + toggle is a small follow-up (one field on a settings model + one check in `generateAndStore`). Deferred to keep 1c bounded; add before Phase 2 if wanted.
- **Native Anthropic, Gemini Vertex/GCP (service-account auth), AWS Bedrock (SigV4)** — each is one adapter task on the existing protocol; `openAICompatible` already covers Anthropic's and Gemini's OpenAI-compat endpoints and Bedrock-via-proxy today.
- **Vision / `completeWithImage`** — all adapters throw `.visionUnsupported`; real multimodal lands with the InBody feature (Phase 4).
- **Session finalization / swap AI calls** (`docs/03` §6.2–6.3) — Phase 2/3; 1c only wires `weeklyPlan`.
- **`FitnessCore` `LLMResult` already carries `cachedTokens`** (added in 1a) — adapters populate it; no core change.

**2. Placeholder scan:** No "TBD"/"implement later" as deliverables. Tasks 15/16 are SwiftUI-heavy — they give the interface + behaviour precisely and full code for the non-view pieces (`CostChip`, `generateAndStore`), with `⌘B` + a described manual check as acceptance, matching how Phase 1b handled its view tasks.

**3. Type consistency:**
- `AdapterKind` cases (`openAICompatible`, `gemini`, `appleOnDevice`) — Tasks 1, 11, 15. ✅
- `LLMProviderFactory.make(kind:baseURL:apiKey:modelID:session:)` — Tasks 11, 14. ✅
- `WeeklyPlanDTO` + `.toDomain(weekStartDate:source:)` + `.planJSONSchema` — Tasks 3, 6, 7, 8, 9. ✅
- `PlanCoordinator(provider:catalog:)` / `makePlan(context:weekStartDate:) async -> CoordinatorResult` / `CoordinatorResult{plan,source,issues,call}` / `CallOutcome` — Tasks 6, 7, 14. ✅
- `AICallRecord.cost(inputTokens:outputTokens:cachedTokens:pricePerMTokIn:pricePerMTokOut:pricePerMTokCached:)` — Tasks 12, 14. ✅
- `CostSummary.from(records:now:)` + `AICallRecordSnapshot{timestamp,costUSD}` — Tasks 13, 16. ✅
- `KeychainStore.set/get/delete(account:)` — Tasks 2, 11, 15. ✅
- `StubLLMProvider(responses:)` / `.callCount` / `.lastUser` — Tasks 5, 6, 7. ✅
- `StubURLProtocol.handler` / `.session()` — Tasks 5, 8, 9. ✅
- Adapter inits: `OpenAICompatibleProvider(baseURL:apiKey:modelID:session:)`, `GeminiProvider(apiKey:modelID:session:baseURL:)`, `FoundationModelsProvider()` — Tasks 8, 9, 10, 11. ✅

---

## Execution Handoff

**1. Inline Execution (recommended, matches Phase 1b)** — the controller writes all non-UI code and runs `xcodebuild test` via CLI; the human performs the `⌘B` / simulator steps in Tasks 15–17 and reports back.

**2. Subagent-Driven** — fresh subagent per task; UI tasks still bounce to the human.
