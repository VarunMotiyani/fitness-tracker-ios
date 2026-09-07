# Phase 1a — FitnessCore Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `FitnessCore` Swift package — a pure, UI-free library that turns a user's training context plus an exercise catalog into a rule-only weekly plan, and validates any plan against the catalog and volume landmarks.

**Architecture:** One SPM package, five library modules with a strict dependency line: `FitnessDomain` (value types, zero deps) ← `ExerciseCatalog` (loads/maps/queries the free-exercise-db dataset) ← `RuleEngine` (split templates, volume landmarks, deterministic plan builder) ← `PlanValidation` (checks a plan). `LLMKit` (the `LLMProvider` protocol + DTOs, no networking) depends only on `FitnessDomain`. Nothing here imports SwiftUI, UIKit, or SwiftData; everything builds and tests with `swift test` on macOS.

**Tech Stack:** Swift 6 (language mode v6, strict concurrency), Swift Package Manager, Swift Testing (`import Testing`), Foundation only.

**Spec:** `docs/03-technical-architecture.md` (§3 data model, §4 catalog, §5 rule engine, §6 AI contract, §7 validation, §10 project structure), with `docs/02-product-design.md` (§1–§4) and `docs/06-decisions.md` (A4, A10, C1, C4, C6, C7). Dataset details: `docs/07-exercise-dataset-research.md`.

## Global Constraints

- **Swift tools version:** `swift-tools-version: 6.2` (bumped from 6.0 during Task 1 — `.iOS(.v26)` needs PackageDescription 6.2+). Requires a Swift 6.2+ toolchain (installed: 6.3.3).
- **Language mode:** `.v6` for every target — strict concurrency checking is complete/on.
- **Platforms:** `.iOS(.v26)`, `.macOS(.v14)`. The macOS floor exists only so `swift test` runs on the dev machine.
- **Swift Testing dependency (Ruling 5, Task 1):** `Package.swift` declares an explicit, version-pinned dependency `.package(url: "https://github.com/swiftlang/swift-testing.git", .upToNextMinor(from: "6.1.0"))`, and every test target lists `.product(name: "Testing", package: "swift-testing")`. This is required because the dev machine runs Command Line Tools only (no full Xcode), which ships the Testing macro plugin but not the `Testing` library module. Do not remove this dependency in Phase 1a. `FitnessCore/Package.resolved` is committed (final-review fix) to pin swift-testing 6.1.3 / swift-syntax 601.0.1 across machines.
- **No Apple UI/persistence frameworks** in this package: no `import SwiftUI`, `import UIKit`, `import SwiftData`, `import Combine`. Foundation only.
- **Every public type is `Sendable`.** Prefer `struct` + `enum`; value semantics throughout.
- **Every type that crosses the AI boundary is `Codable`:** `WeeklyPlan`, `PlannedSession`, `PlannedItem`, `RepRange`, `MuscleVolumeTarget`, `PlanSource`, and every enum they contain.
- **No force-unwraps** (`!`) and no `try!` in non-test code. Fallible paths return optionals or throw.
- **Module names, verbatim:** `FitnessDomain`, `ExerciseCatalog`, `RuleEngine`, `PlanValidation`, `LLMKit`. Package directory: `FitnessCore/` at the repo root.
- **TDD:** write the failing test first, watch it fail, minimal implementation, watch it pass, commit. One task = one commit.
- **Commit message style:** plain, imperative, no body, **no `Co-Authored-By` trailer**. Do **not** run `git push` (the user pushes manually).
- **Volume-landmark and rep-range numbers are seeds** (spec C6) — copy them exactly as written in this plan; they are tuned later from real logs, not now.

---

## File Structure

```
FitnessCore/
├── Package.swift
├── Sources/
│   ├── FitnessDomain/
│   │   ├── Enums.swift              # Goal, ExperienceLevel, MuscleGroup, Equipment, Mechanic, ForceType, Difficulty
│   │   ├── RepRange.swift           # RepRange
│   │   ├── WeeklyPlan.swift         # PlanSource, MuscleVolumeTarget, PlannedItem, PlannedSession, WeeklyPlan
│   │   └── UserContext.swift        # UserContext
│   ├── ExerciseCatalog/
│   │   ├── Exercise.swift           # Exercise
│   │   ├── RawFreeExerciseDB.swift  # RawFreeExerciseDBExercise (Decodable mirror of the dataset)
│   │   ├── FreeExerciseDBMapper.swift # raw JSON record -> Exercise (string→enum maps, heuristics)
│   │   └── CatalogStore.swift       # CatalogStore (load, index, query)
│   ├── RuleEngine/
│   │   ├── VolumeLandmarks.swift    # VolumeBand, VolumeLandmarks.band(for:experience:)
│   │   ├── SplitTemplate.swift      # SplitTemplate, SplitTemplateLibrary
│   │   ├── TemplateSelector.swift   # TemplateSelector.select(sessionsPerWeek:experience:)
│   │   └── RulePlanBuilder.swift    # RulePlanBuilder.build(context:weekStartDate:)
│   ├── PlanValidation/
│   │   └── PlanValidator.swift      # ValidationIssue, PlanValidator.validate(_:context:)
│   └── LLMKit/
│       ├── LLMProvider.swift        # LLMProvider protocol
│       ├── LLMResult.swift          # LLMResult, LLMCallType
│       ├── LLMError.swift           # LLMError
│       └── LLMSchema.swift          # JSONSchema, ImagePayload
└── Tests/
    ├── FitnessDomainTests/
    │   ├── EnumsTests.swift
    │   └── WeeklyPlanCodableTests.swift
    ├── ExerciseCatalogTests/
    │   ├── FreeExerciseDBMapperTests.swift
    │   └── CatalogStoreTests.swift
    ├── RuleEngineTests/
    │   ├── VolumeLandmarksTests.swift
    │   ├── TemplateSelectorTests.swift
    │   └── RulePlanBuilderTests.swift
    ├── PlanValidationTests/
    │   └── PlanValidatorTests.swift
    └── LLMKitTests/
        └── LLMKitTypesTests.swift
```

---

## Task 1: Package scaffold

**Files:**
- Create: `FitnessCore/Package.swift`
- Create (empty stubs, one `// module: X` comment line each): every `Sources/**/**.swift` file listed in File Structure
- Create: `FitnessCore/Sources/FitnessDomain/Placeholder.swift` with `enum _FitnessDomainModule {}` (so each target has ≥1 compilable file); same pattern per module: `_ExerciseCatalogModule`, `_RuleEngineModule`, `_PlanValidationModule`, `_LLMKitModule`

**Interfaces:**
- Consumes: nothing
- Produces: five importable modules — `import FitnessDomain`, `import ExerciseCatalog`, `import RuleEngine`, `import PlanValidation`, `import LLMKit`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FitnessCore",
    platforms: [.iOS(.v26), .macOS(.v14)],
    products: [
        .library(name: "FitnessDomain", targets: ["FitnessDomain"]),
        .library(name: "ExerciseCatalog", targets: ["ExerciseCatalog"]),
        .library(name: "RuleEngine", targets: ["RuleEngine"]),
        .library(name: "PlanValidation", targets: ["PlanValidation"]),
        .library(name: "LLMKit", targets: ["LLMKit"]),
    ],
    targets: [
        .target(name: "FitnessDomain"),
        .target(name: "ExerciseCatalog", dependencies: ["FitnessDomain"]),
        .target(name: "RuleEngine", dependencies: ["FitnessDomain", "ExerciseCatalog"]),
        .target(name: "PlanValidation", dependencies: ["FitnessDomain", "ExerciseCatalog", "RuleEngine"]),
        .target(name: "LLMKit", dependencies: ["FitnessDomain"]),
        .testTarget(name: "FitnessDomainTests", dependencies: ["FitnessDomain"]),
        .testTarget(name: "ExerciseCatalogTests", dependencies: ["ExerciseCatalog"]),
        .testTarget(name: "RuleEngineTests", dependencies: ["RuleEngine", "ExerciseCatalog"]),
        .testTarget(name: "PlanValidationTests", dependencies: ["PlanValidation"]),
        .testTarget(name: "LLMKitTests", dependencies: ["LLMKit"]),
    ],
    swiftLanguageModes: [.v6]
)
```

- [ ] **Step 2: Create one placeholder file per source module**

`FitnessCore/Sources/FitnessDomain/Placeholder.swift`:
```swift
enum _FitnessDomainModule {}
```
Repeat with the matching name in `ExerciseCatalog/`, `RuleEngine/`, `PlanValidation/`, `LLMKit/`.

- [ ] **Step 3: Create one placeholder test per test target**

`FitnessCore/Tests/FitnessDomainTests/SmokeTests.swift`:
```swift
import Testing

@Test func moduleLoads() {
    #expect(Bool(true))
}
```
Repeat in each of the five `Tests/*Tests/` directories.

- [ ] **Step 4: Build and test**

Run: `cd FitnessCore && swift build && swift test`
Expected: build succeeds; 5 smoke tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/vmotiyani/Documents/person/fitness-tracker-ios
git add FitnessCore
git commit -m "Scaffold FitnessCore package with five modules"
```

---

## Task 2: FitnessDomain — core enums

**Files:**
- Create: `FitnessCore/Sources/FitnessDomain/Enums.swift`
- Delete: `FitnessCore/Sources/FitnessDomain/Placeholder.swift`
- Test: `FitnessCore/Tests/FitnessDomainTests/EnumsTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `enum Goal: String, Codable, Sendable, CaseIterable { case loseFat, buildMuscle, getStronger, generalFitness }`
  - `enum ExperienceLevel: String, Codable, Sendable, CaseIterable { case beginner, intermediate, advanced }`
  - `enum MuscleGroup: String, Codable, Sendable, CaseIterable { case chest, back, lowerBack, traps, shoulders, biceps, triceps, forearms, quads, hamstrings, glutes, calves, abs }`
  - `enum Equipment: String, Codable, Sendable, CaseIterable { case barbell, dumbbell, cable, machine, bodyweight, kettlebell, bands, ezBar, other }`
  - `enum Mechanic: String, Codable, Sendable { case compound, isolation, unknown }`
  - `enum ForceType: String, Codable, Sendable { case push, pull, `static` }`
  - `enum Difficulty: String, Codable, Sendable { case beginner, intermediate, expert }`

- [ ] **Step 1: Write the failing test**

`EnumsTests.swift`:
```swift
import Testing
@testable import FitnessDomain

@Test func muscleGroupRoundTripsThroughRawValue() throws {
    for muscle in MuscleGroup.allCases {
        #expect(MuscleGroup(rawValue: muscle.rawValue) == muscle)
    }
}

@Test func equipmentHasStableRawValues() {
    #expect(Equipment.bodyweight.rawValue == "bodyweight")
    #expect(Equipment.ezBar.rawValue == "ezBar")
}

@Test func forceTypeStaticRawValue() {
    #expect(ForceType.static.rawValue == "static")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd FitnessCore && swift test --filter FitnessDomainTests`
Expected: FAIL — `MuscleGroup` / `Equipment` / `ForceType` not in scope.

- [ ] **Step 3: Write `Enums.swift`**

```swift
public enum Goal: String, Codable, Sendable, CaseIterable {
    case loseFat, buildMuscle, getStronger, generalFitness
}

public enum ExperienceLevel: String, Codable, Sendable, CaseIterable {
    case beginner, intermediate, advanced
}

public enum MuscleGroup: String, Codable, Sendable, CaseIterable {
    case chest, back, lowerBack, traps, shoulders
    case biceps, triceps, forearms
    case quads, hamstrings, glutes, calves
    case abs
}

public enum Equipment: String, Codable, Sendable, CaseIterable {
    case barbell, dumbbell, cable, machine, bodyweight, kettlebell, bands, ezBar, other
}

public enum Mechanic: String, Codable, Sendable {
    case compound, isolation, unknown
}

public enum ForceType: String, Codable, Sendable {
    case push, pull
    case `static`
}

public enum Difficulty: String, Codable, Sendable {
    case beginner, intermediate, expert
}
```

Then delete `Placeholder.swift`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd FitnessCore && swift test --filter FitnessDomainTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add FitnessCore
git commit -m "Add FitnessDomain core enums"
```

---

## Task 3: FitnessDomain — RepRange and WeeklyPlan value types

**Files:**
- Create: `FitnessCore/Sources/FitnessDomain/RepRange.swift`
- Create: `FitnessCore/Sources/FitnessDomain/WeeklyPlan.swift`
- Test: `FitnessCore/Tests/FitnessDomainTests/WeeklyPlanCodableTests.swift`

**Interfaces:**
- Consumes: `MuscleGroup` (Task 2)
- Produces:
  - `struct RepRange: Codable, Sendable, Equatable { let min: Int; let max: Int; init(min:Int, max:Int) }`
  - `enum PlanSource: String, Codable, Sendable { case ruleEngine, ai, fallback }`
  - `struct MuscleVolumeTarget: Codable, Sendable, Equatable { let muscle: MuscleGroup; let targetSets: Int }`
  - `struct PlannedItem: Codable, Sendable, Equatable { let exerciseID: String; let targetSets: Int; let targetReps: RepRange; let targetLoadKg: Double?; let restSeconds: Int; let coachNote: String }`
  - `struct PlannedSession: Codable, Sendable, Equatable, Identifiable { let id: UUID; let order: Int; let focusMuscles: [MuscleGroup]; let items: [PlannedItem] }`
  - `struct WeeklyPlan: Codable, Sendable, Equatable { let weekStartDate: Date; let source: PlanSource; let rationale: String; let sessions: [PlannedSession]; let weeklyVolumeTargets: [MuscleVolumeTarget] }`

- [ ] **Step 1: Write the failing test**

`WeeklyPlanCodableTests.swift`:
```swift
import Testing
import Foundation
@testable import FitnessDomain

@Test func weeklyPlanEncodesAndDecodesUnchanged() throws {
    let plan = WeeklyPlan(
        weekStartDate: Date(timeIntervalSince1970: 1_700_000_000),
        source: .ruleEngine,
        rationale: "3-day full body",
        sessions: [
            PlannedSession(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                order: 0,
                focusMuscles: [.chest, .back],
                items: [
                    PlannedItem(exerciseID: "Barbell_Bench_Press",
                                targetSets: 3,
                                targetReps: RepRange(min: 5, max: 8),
                                targetLoadKg: nil,
                                restSeconds: 150,
                                coachNote: "Leave 2 reps in the tank.")
                ]
            )
        ],
        weeklyVolumeTargets: [MuscleVolumeTarget(muscle: .chest, targetSets: 12)]
    )

    let data = try JSONEncoder().encode(plan)
    let decoded = try JSONDecoder().decode(WeeklyPlan.self, from: data)
    #expect(decoded == plan)
}

@Test func repRangeIsEquatable() {
    #expect(RepRange(min: 8, max: 12) == RepRange(min: 8, max: 12))
    #expect(RepRange(min: 8, max: 12) != RepRange(min: 8, max: 10))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd FitnessCore && swift test --filter WeeklyPlanCodableTests`
Expected: FAIL — `WeeklyPlan` / `RepRange` not in scope.

- [ ] **Step 3: Write the implementation**

`RepRange.swift`:
```swift
public struct RepRange: Codable, Sendable, Equatable {
    public let min: Int
    public let max: Int
    public init(min: Int, max: Int) {
        self.min = min
        self.max = max
    }
}
```

`WeeklyPlan.swift`:
```swift
import Foundation

public enum PlanSource: String, Codable, Sendable {
    case ruleEngine, ai, fallback
}

public struct MuscleVolumeTarget: Codable, Sendable, Equatable {
    public let muscle: MuscleGroup
    public let targetSets: Int
    public init(muscle: MuscleGroup, targetSets: Int) {
        self.muscle = muscle
        self.targetSets = targetSets
    }
}

public struct PlannedItem: Codable, Sendable, Equatable {
    public let exerciseID: String
    public let targetSets: Int
    public let targetReps: RepRange
    public let targetLoadKg: Double?
    public let restSeconds: Int
    public let coachNote: String
    public init(exerciseID: String, targetSets: Int, targetReps: RepRange,
                targetLoadKg: Double?, restSeconds: Int, coachNote: String) {
        self.exerciseID = exerciseID
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetLoadKg = targetLoadKg
        self.restSeconds = restSeconds
        self.coachNote = coachNote
    }
}

public struct PlannedSession: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let order: Int
    public let focusMuscles: [MuscleGroup]
    public let items: [PlannedItem]
    public init(id: UUID, order: Int, focusMuscles: [MuscleGroup], items: [PlannedItem]) {
        self.id = id
        self.order = order
        self.focusMuscles = focusMuscles
        self.items = items
    }
}

public struct WeeklyPlan: Codable, Sendable, Equatable {
    public let weekStartDate: Date
    public let source: PlanSource
    public let rationale: String
    public let sessions: [PlannedSession]
    public let weeklyVolumeTargets: [MuscleVolumeTarget]
    public init(weekStartDate: Date, source: PlanSource, rationale: String,
                sessions: [PlannedSession], weeklyVolumeTargets: [MuscleVolumeTarget]) {
        self.weekStartDate = weekStartDate
        self.source = source
        self.rationale = rationale
        self.sessions = sessions
        self.weeklyVolumeTargets = weeklyVolumeTargets
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd FitnessCore && swift test --filter WeeklyPlanCodableTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add FitnessCore
git commit -m "Add FitnessDomain WeeklyPlan value types"
```

---

## Task 4: FitnessDomain — UserContext

**Files:**
- Create: `FitnessCore/Sources/FitnessDomain/UserContext.swift`
- Test: `FitnessCore/Tests/FitnessDomainTests/UserContextTests.swift`

**Interfaces:**
- Consumes: `Goal`, `ExperienceLevel`, `Equipment`, `MuscleGroup` (Task 2)
- Produces:
  - `struct UserContext: Sendable, Equatable { let goal: Goal; let experience: ExperienceLevel; let sessionsPerWeek: Int; let sessionLengthMinutes: Int; let availableEquipment: Set<Equipment>; let excludedExerciseIDs: Set<String>; let excludedMuscles: Set<MuscleGroup>; init(...) }`

- [ ] **Step 1: Write the failing test**

`UserContextTests.swift`:
```swift
import Testing
@testable import FitnessDomain

@Test func userContextStoresAllInputs() {
    let ctx = UserContext(
        goal: .buildMuscle,
        experience: .intermediate,
        sessionsPerWeek: 4,
        sessionLengthMinutes: 60,
        availableEquipment: [.barbell, .dumbbell, .cable],
        excludedExerciseIDs: ["Barbell_Deadlift"],
        excludedMuscles: [.lowerBack]
    )
    #expect(ctx.sessionsPerWeek == 4)
    #expect(ctx.availableEquipment.contains(.cable))
    #expect(ctx.excludedMuscles.contains(.lowerBack))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd FitnessCore && swift test --filter UserContextTests`
Expected: FAIL — `UserContext` not in scope.

- [ ] **Step 3: Write `UserContext.swift`**

```swift
public struct UserContext: Sendable, Equatable {
    public let goal: Goal
    public let experience: ExperienceLevel
    public let sessionsPerWeek: Int
    public let sessionLengthMinutes: Int
    public let availableEquipment: Set<Equipment>
    public let excludedExerciseIDs: Set<String>
    public let excludedMuscles: Set<MuscleGroup>

    public init(goal: Goal,
                experience: ExperienceLevel,
                sessionsPerWeek: Int,
                sessionLengthMinutes: Int,
                availableEquipment: Set<Equipment>,
                excludedExerciseIDs: Set<String>,
                excludedMuscles: Set<MuscleGroup>) {
        self.goal = goal
        self.experience = experience
        self.sessionsPerWeek = sessionsPerWeek
        self.sessionLengthMinutes = sessionLengthMinutes
        self.availableEquipment = availableEquipment
        self.excludedExerciseIDs = excludedExerciseIDs
        self.excludedMuscles = excludedMuscles
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd FitnessCore && swift test --filter UserContextTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add FitnessCore
git commit -m "Add FitnessDomain UserContext"
```

---

## Task 5: ExerciseCatalog — Exercise type

**Files:**
- Create: `FitnessCore/Sources/ExerciseCatalog/Exercise.swift`
- Delete: `FitnessCore/Sources/ExerciseCatalog/Placeholder.swift`
- Test: `FitnessCore/Tests/ExerciseCatalogTests/ExerciseTests.swift`

**Interfaces:**
- Consumes: `MuscleGroup`, `Equipment`, `Mechanic`, `ForceType`, `Difficulty` (Task 2) via `import FitnessDomain`
- Produces:
  - `struct Exercise: Codable, Sendable, Equatable, Identifiable { let id: String; let name: String; let primaryMuscle: MuscleGroup; let secondaryMuscles: [MuscleGroup]; let equipment: Equipment; let mechanic: Mechanic; let force: ForceType?; let difficulty: Difficulty; let isUnilateral: Bool; let instructions: [String]; let imagePaths: [String]; init(...) }`

- [ ] **Step 1: Write the failing test**

`ExerciseTests.swift`:
```swift
import Testing
import FitnessDomain
@testable import ExerciseCatalog

@Test func exerciseIsIdentifiableByID() {
    let ex = Exercise(id: "Barbell_Bench_Press", name: "Barbell Bench Press",
                      primaryMuscle: .chest, secondaryMuscles: [.triceps, .shoulders],
                      equipment: .barbell, mechanic: .compound, force: .push,
                      difficulty: .beginner, isUnilateral: false,
                      instructions: ["Lie on the bench."], imagePaths: ["Barbell_Bench_Press/0.jpg"])
    #expect(ex.id == "Barbell_Bench_Press")
    #expect(ex.secondaryMuscles.contains(.triceps))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd FitnessCore && swift test --filter ExerciseTests`
Expected: FAIL — `Exercise` not in scope.

- [ ] **Step 3: Write `Exercise.swift`**

```swift
import FitnessDomain

public struct Exercise: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let primaryMuscle: MuscleGroup
    public let secondaryMuscles: [MuscleGroup]
    public let equipment: Equipment
    public let mechanic: Mechanic
    public let force: ForceType?
    public let difficulty: Difficulty
    public let isUnilateral: Bool
    public let instructions: [String]
    public let imagePaths: [String]

    public init(id: String, name: String, primaryMuscle: MuscleGroup,
                secondaryMuscles: [MuscleGroup], equipment: Equipment,
                mechanic: Mechanic, force: ForceType?, difficulty: Difficulty,
                isUnilateral: Bool, instructions: [String], imagePaths: [String]) {
        self.id = id
        self.name = name
        self.primaryMuscle = primaryMuscle
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.mechanic = mechanic
        self.force = force
        self.difficulty = difficulty
        self.isUnilateral = isUnilateral
        self.instructions = instructions
        self.imagePaths = imagePaths
    }
}
```

Then delete `Placeholder.swift`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd FitnessCore && swift test --filter ExerciseTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add FitnessCore
git commit -m "Add ExerciseCatalog Exercise type"
```

---

## Task 6: ExerciseCatalog — free-exercise-db mapper

**Files:**
- Create: `FitnessCore/Sources/ExerciseCatalog/RawFreeExerciseDB.swift`
- Create: `FitnessCore/Sources/ExerciseCatalog/FreeExerciseDBMapper.swift`
- Test: `FitnessCore/Tests/ExerciseCatalogTests/FreeExerciseDBMapperTests.swift`

**Interfaces:**
- Consumes: `Exercise` (Task 5); `MuscleGroup`, `Equipment`, `Mechanic`, `ForceType`, `Difficulty` (Task 2)
- Produces:
  - `struct RawFreeExerciseDBExercise: Decodable, Sendable { let id: String?; let name: String; let force: String?; let level: String; let mechanic: String?; let equipment: String?; let primaryMuscles: [String]; let secondaryMuscles: [String]; let instructions: [String]; let category: String; let images: [String] }`
  - `enum FreeExerciseDBMapper { static func map(_ raw: RawFreeExerciseDBExercise) -> Exercise? }`
  - `map` returns `nil` when `primaryMuscles` is empty or its first entry has no `MuscleGroup` mapping.

**Reference — string maps (use exactly):**

`muscle` (lowercased free-exercise-db value → `MuscleGroup`):
`"chest" → .chest`, `"lats" → .back`, `"middle back" → .back`, `"lower back" → .lowerBack`, `"traps" → .traps`, `"neck" → .traps`, `"shoulders" → .shoulders`, `"biceps" → .biceps`, `"triceps" → .triceps`, `"forearms" → .forearms`, `"quadriceps" → .quads`, `"hamstrings" → .hamstrings`, `"glutes" → .glutes`, `"calves" → .calves`, `"abdominals" → .abs`, `"abductors" → .glutes`, `"adductors" → .glutes`. Anything else → `nil`.

`equipment` (lowercased → `Equipment`):
`"barbell" → .barbell`, `"dumbbell" → .dumbbell`, `"cable" → .cable`, `"machine" → .machine`, `"body only" → .bodyweight`, `"kettlebells" → .kettlebell`, `"bands" → .bands`, `"e-z curl bar" → .ezBar`. Anything else or `nil` → `.other`.

`mechanic`: `"compound" → .compound`, `"isolation" → .isolation`, else/`nil` → `.unknown`.
`force`: `"push" → .push`, `"pull" → .pull`, `"static" → .static`, else/`nil` → `nil`.
`level`: `"beginner" → .beginner`, `"intermediate" → .intermediate`, `"expert" → .expert`, else → `.intermediate`.

`id`: `raw.id ?? raw.name.replacingOccurrences(of: " ", with: "_")`.
`isUnilateral`: `true` if `raw.name.lowercased()` contains any of `"single-arm"`, `"single arm"`, `"one-arm"`, `"one arm"`, `"single-leg"`, `"single leg"`, `"one-leg"`, `"one leg"`, `"alternating"`, `"alternate"`.
`secondaryMuscles`: map each entry, drop unmapped, dedupe preserving order.

- [ ] **Step 1: Write the failing test**

`FreeExerciseDBMapperTests.swift`:
```swift
import Testing
import Foundation
import FitnessDomain
@testable import ExerciseCatalog

private let sampleJSON = """
{
  "id": "Alternate_Incline_Dumbbell_Curl",
  "name": "Alternate Incline Dumbbell Curl",
  "force": "pull",
  "level": "beginner",
  "mechanic": "isolation",
  "equipment": "dumbbell",
  "primaryMuscles": ["biceps"],
  "secondaryMuscles": ["forearms"],
  "instructions": ["Sit down on an incline bench."],
  "category": "strength",
  "images": ["Alternate_Incline_Dumbbell_Curl/0.jpg", "Alternate_Incline_Dumbbell_Curl/1.jpg"]
}
""".data(using: .utf8)!

@Test func mapsAKnownRecord() throws {
    let raw = try JSONDecoder().decode(RawFreeExerciseDBExercise.self, from: sampleJSON)
    let ex = try #require(FreeExerciseDBMapper.map(raw))
    #expect(ex.id == "Alternate_Incline_Dumbbell_Curl")
    #expect(ex.primaryMuscle == .biceps)
    #expect(ex.secondaryMuscles == [.forearms])
    #expect(ex.equipment == .dumbbell)
    #expect(ex.mechanic == .isolation)
    #expect(ex.force == .pull)
    #expect(ex.isUnilateral == true)          // "Alternate" in the name
}

@Test func returnsNilWhenPrimaryMuscleUnmappable() throws {
    let json = """
    {"name":"Neck Curl","level":"beginner","primaryMuscles":["shins"],
     "secondaryMuscles":[],"instructions":[],"category":"strength","images":[]}
    """.data(using: .utf8)!
    let raw = try JSONDecoder().decode(RawFreeExerciseDBExercise.self, from: json)
    #expect(FreeExerciseDBMapper.map(raw) == nil)
}

@Test func unknownEquipmentBecomesOther() throws {
    let json = """
    {"name":"Foam Roll IT Band","level":"beginner","equipment":"foam roll",
     "primaryMuscles":["quadriceps"],"secondaryMuscles":[],"instructions":[],
     "category":"stretching","images":[]}
    """.data(using: .utf8)!
    let raw = try JSONDecoder().decode(RawFreeExerciseDBExercise.self, from: json)
    let ex = try #require(FreeExerciseDBMapper.map(raw))
    #expect(ex.equipment == .other)
    #expect(ex.force == nil)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd FitnessCore && swift test --filter FreeExerciseDBMapperTests`
Expected: FAIL — `RawFreeExerciseDBExercise` / `FreeExerciseDBMapper` not in scope.

- [ ] **Step 3: Write the implementation**

`RawFreeExerciseDB.swift`:
```swift
public struct RawFreeExerciseDBExercise: Decodable, Sendable {
    public let id: String?
    public let name: String
    public let force: String?
    public let level: String
    public let mechanic: String?
    public let equipment: String?
    public let primaryMuscles: [String]
    public let secondaryMuscles: [String]
    public let instructions: [String]
    public let category: String
    public let images: [String]
}
```

`FreeExerciseDBMapper.swift`:
```swift
import FitnessDomain

public enum FreeExerciseDBMapper {

    public static func map(_ raw: RawFreeExerciseDBExercise) -> Exercise? {
        guard let firstPrimary = raw.primaryMuscles.first,
              let primary = muscle(firstPrimary) else {
            return nil
        }

        var seenSecondary: Set<MuscleGroup> = [primary]
        var secondaries: [MuscleGroup] = []
        for name in raw.secondaryMuscles {
            guard let m = muscle(name), !seenSecondary.contains(m) else { continue }
            seenSecondary.insert(m)
            secondaries.append(m)
        }

        return Exercise(
            id: raw.id ?? raw.name.replacingOccurrences(of: " ", with: "_"),
            name: raw.name,
            primaryMuscle: primary,
            secondaryMuscles: secondaries,
            equipment: equipment(raw.equipment),
            mechanic: mechanic(raw.mechanic),
            force: force(raw.force),
            difficulty: difficulty(raw.level),
            isUnilateral: isUnilateral(raw.name),
            instructions: raw.instructions,
            imagePaths: raw.images
        )
    }

    static func muscle(_ value: String) -> MuscleGroup? {
        switch value.lowercased() {
        case "chest": return .chest
        case "lats", "middle back": return .back
        case "lower back": return .lowerBack
        case "traps", "neck": return .traps
        case "shoulders": return .shoulders
        case "biceps": return .biceps
        case "triceps": return .triceps
        case "forearms": return .forearms
        case "quadriceps": return .quads
        case "hamstrings": return .hamstrings
        case "glutes", "abductors", "adductors": return .glutes
        case "calves": return .calves
        case "abdominals": return .abs
        default: return nil
        }
    }

    static func equipment(_ value: String?) -> Equipment {
        switch value?.lowercased() {
        case "barbell": return .barbell
        case "dumbbell": return .dumbbell
        case "cable": return .cable
        case "machine": return .machine
        case "body only": return .bodyweight
        case "kettlebells": return .kettlebell
        case "bands": return .bands
        case "e-z curl bar": return .ezBar
        default: return .other
        }
    }

    static func mechanic(_ value: String?) -> Mechanic {
        switch value?.lowercased() {
        case "compound": return .compound
        case "isolation": return .isolation
        default: return .unknown
        }
    }

    static func force(_ value: String?) -> ForceType? {
        switch value?.lowercased() {
        case "push": return .push
        case "pull": return .pull
        case "static": return .static
        default: return nil
        }
    }

    static func difficulty(_ value: String) -> Difficulty {
        switch value.lowercased() {
        case "beginner": return .beginner
        case "expert": return .expert
        default: return .intermediate
        }
    }

    static func isUnilateral(_ name: String) -> Bool {
        let n = name.lowercased()
        let markers = ["single-arm", "single arm", "one-arm", "one arm",
                       "single-leg", "single leg", "one-leg", "one leg",
                       "alternating", "alternate"]
        return markers.contains { n.contains($0) }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd FitnessCore && swift test --filter FreeExerciseDBMapperTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add FitnessCore
git commit -m "Add free-exercise-db to Exercise mapper"
```

---

## Task 7: ExerciseCatalog — CatalogStore

**Files:**
- Create: `FitnessCore/Sources/ExerciseCatalog/CatalogStore.swift`
- Test: `FitnessCore/Tests/ExerciseCatalogTests/CatalogStoreTests.swift`

**Interfaces:**
- Consumes: `Exercise` (Task 5), `RawFreeExerciseDBExercise` + `FreeExerciseDBMapper` (Task 6), `MuscleGroup` + `Equipment` (Task 2)
- Produces:
  - `struct CatalogStore: Sendable`
    - `init(exercises: [Exercise])`
    - `static func load(fromJSONData data: Data) throws -> CatalogStore` — decodes `[RawFreeExerciseDBExercise]`, maps each, silently drops records that map to `nil`, dedupes by `id` keeping the first
    - `var all: [Exercise] { get }` — insertion order
    - `func exercise(id: String) -> Exercise?`
    - `func contains(id: String) -> Bool`
    - `func exercises(primaryMuscle: MuscleGroup, availableEquipment: Set<Equipment>) -> [Exercise]` — filtered by primary muscle AND `availableEquipment.contains(exercise.equipment)`, returned sorted by `name` ascending for determinism
  - `enum CatalogError: Error, Sendable, Equatable { case empty }` — `load` throws `.empty` if zero records map successfully

- [ ] **Step 1: Write the failing test**

`CatalogStoreTests.swift`:
```swift
import Testing
import Foundation
import FitnessDomain
@testable import ExerciseCatalog

private let twoRecords = """
[
  {"id":"Barbell_Bench_Press","name":"Barbell Bench Press","force":"push","level":"beginner",
   "mechanic":"compound","equipment":"barbell","primaryMuscles":["chest"],
   "secondaryMuscles":["triceps","shoulders"],"instructions":["Lie down."],"category":"strength","images":[]},
  {"id":"Cable_Fly","name":"Cable Fly","force":"push","level":"intermediate",
   "mechanic":"isolation","equipment":"cable","primaryMuscles":["chest"],
   "secondaryMuscles":[],"instructions":["Stand tall."],"category":"strength","images":[]}
]
""".data(using: .utf8)!

@Test func loadsAndIndexesByID() throws {
    let store = try CatalogStore.load(fromJSONData: twoRecords)
    #expect(store.all.count == 2)
    #expect(store.contains(id: "Cable_Fly"))
    #expect(store.exercise(id: "Barbell_Bench_Press")?.primaryMuscle == .chest)
}

@Test func filtersByMuscleAndEquipment() throws {
    let store = try CatalogStore.load(fromJSONData: twoRecords)
    let barbellChest = store.exercises(primaryMuscle: .chest, availableEquipment: [.barbell])
    #expect(barbellChest.map(\.id) == ["Barbell_Bench_Press"])

    let allChest = store.exercises(primaryMuscle: .chest, availableEquipment: [.barbell, .cable])
    #expect(allChest.map(\.id) == ["Barbell_Bench_Press", "Cable_Fly"])   // sorted by name
}

@Test func loadThrowsWhenNothingMaps() {
    let junk = "[]".data(using: .utf8)!
    #expect(throws: CatalogError.empty) {
        _ = try CatalogStore.load(fromJSONData: junk)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd FitnessCore && swift test --filter CatalogStoreTests`
Expected: FAIL — `CatalogStore` not in scope.

- [ ] **Step 3: Write `CatalogStore.swift`**

```swift
import Foundation
import FitnessDomain

public enum CatalogError: Error, Sendable, Equatable {
    case empty
}

public struct CatalogStore: Sendable {
    public let all: [Exercise]
    private let byID: [String: Exercise]

    public init(exercises: [Exercise]) {
        var ordered: [Exercise] = []
        var index: [String: Exercise] = [:]
        for exercise in exercises where index[exercise.id] == nil {
            index[exercise.id] = exercise
            ordered.append(exercise)
        }
        self.all = ordered
        self.byID = index
    }

    public static func load(fromJSONData data: Data) throws -> CatalogStore {
        let raw = try JSONDecoder().decode([RawFreeExerciseDBExercise].self, from: data)
        let mapped = raw.compactMap(FreeExerciseDBMapper.map)
        guard !mapped.isEmpty else { throw CatalogError.empty }
        return CatalogStore(exercises: mapped)
    }

    public func exercise(id: String) -> Exercise? { byID[id] }

    public func contains(id: String) -> Bool { byID[id] != nil }

    public func exercises(primaryMuscle: MuscleGroup,
                          availableEquipment: Set<Equipment>) -> [Exercise] {
        all.filter { $0.primaryMuscle == primaryMuscle && availableEquipment.contains($0.equipment) }
           .sorted { $0.name < $1.name }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd FitnessCore && swift test --filter CatalogStoreTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add FitnessCore
git commit -m "Add CatalogStore with load, index, and query"
```

---

## Task 8: RuleEngine — VolumeLandmarks

**Files:**
- Create: `FitnessCore/Sources/RuleEngine/VolumeLandmarks.swift`
- Delete: `FitnessCore/Sources/RuleEngine/Placeholder.swift`
- Test: `FitnessCore/Tests/RuleEngineTests/VolumeLandmarksTests.swift`

**Interfaces:**
- Consumes: `MuscleGroup`, `ExperienceLevel` (Task 2) via `import FitnessDomain`
- Produces:
  - `struct VolumeBand: Sendable, Equatable { let mev: Int; let mav: Int; let mrv: Int; init(mev:Int, mav:Int, mrv:Int) }`
  - `enum VolumeLandmarks { static func band(for muscle: MuscleGroup, experience: ExperienceLevel) -> VolumeBand }`
  - Table below is authoritative; copy verbatim. `advanced` reuses the `intermediate` row **except** where a distinct row is given. For P1a, provide explicit rows for `beginner` and `intermediate`; `advanced` maps to the `intermediate` row.

**Weekly working-set landmark table (mev / mav / mrv):**

| Muscle | beginner | intermediate (+advanced) |
|---|---|---|
| chest | 6 / 12 / 18 | 8 / 16 / 22 |
| back | 8 / 14 / 20 | 10 / 18 / 25 |
| lowerBack | 2 / 6 / 10 | 2 / 8 / 12 |
| traps | 0 / 6 / 12 | 2 / 10 / 16 |
| shoulders | 6 / 12 / 18 | 8 / 16 / 22 |
| biceps | 5 / 10 / 16 | 6 / 14 / 20 |
| triceps | 4 / 10 / 14 | 6 / 12 / 18 |
| forearms | 0 / 4 / 8 | 2 / 6 / 10 |
| quads | 6 / 12 / 18 | 8 / 16 / 22 |
| hamstrings | 4 / 10 / 16 | 6 / 13 / 18 |
| glutes | 0 / 8 / 14 | 4 / 10 / 16 |
| calves | 6 / 12 / 16 | 8 / 14 / 18 |
| abs | 0 / 10 / 16 | 4 / 12 / 20 |

- [ ] **Step 1: Write the failing test**

`VolumeLandmarksTests.swift`:
```swift
import Testing
import FitnessDomain
@testable import RuleEngine

@Test func beginnerChestBand() {
    let band = VolumeLandmarks.band(for: .chest, experience: .beginner)
    #expect(band == VolumeBand(mev: 6, mav: 12, mrv: 18))
}

@Test func advancedReusesIntermediateRow() {
    #expect(VolumeLandmarks.band(for: .back, experience: .advanced)
            == VolumeLandmarks.band(for: .back, experience: .intermediate))
}

@Test func everyMuscleHasABand() {
    for muscle in MuscleGroup.allCases {
        let band = VolumeLandmarks.band(for: muscle, experience: .intermediate)
        #expect(band.mev <= band.mav && band.mav <= band.mrv)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd FitnessCore && swift test --filter VolumeLandmarksTests`
Expected: FAIL — `VolumeLandmarks` / `VolumeBand` not in scope.

- [ ] **Step 3: Write `VolumeLandmarks.swift`**

```swift
import FitnessDomain

public struct VolumeBand: Sendable, Equatable {
    public let mev: Int
    public let mav: Int
    public let mrv: Int
    public init(mev: Int, mav: Int, mrv: Int) {
        self.mev = mev
        self.mav = mav
        self.mrv = mrv
    }
}

public enum VolumeLandmarks {

    public static func band(for muscle: MuscleGroup,
                            experience: ExperienceLevel) -> VolumeBand {
        switch experience {
        case .beginner:                 return beginner[muscle] ?? fallback
        case .intermediate, .advanced:  return intermediate[muscle] ?? fallback
        }
    }

    private static let fallback = VolumeBand(mev: 4, mav: 10, mrv: 16)

    private static let beginner: [MuscleGroup: VolumeBand] = [
        .chest:      VolumeBand(mev: 6,  mav: 12, mrv: 18),
        .back:       VolumeBand(mev: 8,  mav: 14, mrv: 20),
        .lowerBack:  VolumeBand(mev: 2,  mav: 6,  mrv: 10),
        .traps:      VolumeBand(mev: 0,  mav: 6,  mrv: 12),
        .shoulders:  VolumeBand(mev: 6,  mav: 12, mrv: 18),
        .biceps:     VolumeBand(mev: 5,  mav: 10, mrv: 16),
        .triceps:    VolumeBand(mev: 4,  mav: 10, mrv: 14),
        .forearms:   VolumeBand(mev: 0,  mav: 4,  mrv: 8),
        .quads:      VolumeBand(mev: 6,  mav: 12, mrv: 18),
        .hamstrings: VolumeBand(mev: 4,  mav: 10, mrv: 16),
        .glutes:     VolumeBand(mev: 0,  mav: 8,  mrv: 14),
        .calves:     VolumeBand(mev: 6,  mav: 12, mrv: 16),
        .abs:        VolumeBand(mev: 0,  mav: 10, mrv: 16),
    ]

    private static let intermediate: [MuscleGroup: VolumeBand] = [
        .chest:      VolumeBand(mev: 8,  mav: 16, mrv: 22),
        .back:       VolumeBand(mev: 10, mav: 18, mrv: 25),
        .lowerBack:  VolumeBand(mev: 2,  mav: 8,  mrv: 12),
        .traps:      VolumeBand(mev: 2,  mav: 10, mrv: 16),
        .shoulders:  VolumeBand(mev: 8,  mav: 16, mrv: 22),
        .biceps:     VolumeBand(mev: 6,  mav: 14, mrv: 20),
        .triceps:    VolumeBand(mev: 6,  mav: 12, mrv: 18),
        .forearms:   VolumeBand(mev: 2,  mav: 6,  mrv: 10),
        .quads:      VolumeBand(mev: 8,  mav: 16, mrv: 22),
        .hamstrings: VolumeBand(mev: 6,  mav: 13, mrv: 18),
        .glutes:     VolumeBand(mev: 4,  mav: 10, mrv: 16),
        .calves:     VolumeBand(mev: 8,  mav: 14, mrv: 18),
        .abs:        VolumeBand(mev: 4,  mav: 12, mrv: 20),
    ]
}
```

Then delete `Placeholder.swift`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd FitnessCore && swift test --filter VolumeLandmarksTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add FitnessCore
git commit -m "Add RuleEngine volume landmark table"
```

---

## Task 9: RuleEngine — SplitTemplate library

**Files:**
- Create: `FitnessCore/Sources/RuleEngine/SplitTemplate.swift`
- Test: `FitnessCore/Tests/RuleEngineTests/SplitTemplateTests.swift`

**Interfaces:**
- Consumes: `MuscleGroup` (Task 2)
- Produces:
  - `struct SplitTemplate: Sendable, Equatable { let name: String; let sessionFocuses: [[MuscleGroup]]; var sessionCount: Int { sessionFocuses.count }; init(name:String, sessionFocuses:[[MuscleGroup]]) }`
  - `enum SplitTemplateLibrary { static let fullBody3: SplitTemplate; static let upperLower4: SplitTemplate; static let pushPullLegs6: SplitTemplate; static let all: [SplitTemplate] }`

**Template definitions (use exactly):**
- `fullBody3` — 3 sessions, each: `[.quads, .hamstrings, .glutes, .chest, .back, .shoulders, .biceps, .triceps, .abs]`
- `upperLower4` — 4 sessions: upper `[.chest, .back, .shoulders, .biceps, .triceps]`, lower `[.quads, .hamstrings, .glutes, .calves, .abs]`, upper, lower
- `pushPullLegs6` — 6 sessions: push `[.chest, .shoulders, .triceps]`, pull `[.back, .biceps, .traps]`, legs `[.quads, .hamstrings, .glutes, .calves]`, then push, pull, legs again

- [ ] **Step 1: Write the failing test**

`SplitTemplateTests.swift`:
```swift
import Testing
import FitnessDomain
@testable import RuleEngine

@Test func fullBodyHasThreeIdenticalSessions() {
    let t = SplitTemplateLibrary.fullBody3
    #expect(t.sessionCount == 3)
    #expect(t.sessionFocuses[0] == t.sessionFocuses[2])
    #expect(t.sessionFocuses[0].contains(.chest))
}

@Test func upperLowerAlternates() {
    let t = SplitTemplateLibrary.upperLower4
    #expect(t.sessionCount == 4)
    #expect(t.sessionFocuses[0].contains(.chest))
    #expect(t.sessionFocuses[1].contains(.quads))
    #expect(t.sessionFocuses[0] == t.sessionFocuses[2])
}

@Test func libraryListsAllTemplates() {
    #expect(SplitTemplateLibrary.all.count == 3)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd FitnessCore && swift test --filter SplitTemplateTests`
Expected: FAIL — `SplitTemplate` not in scope.

- [ ] **Step 3: Write `SplitTemplate.swift`**

```swift
import FitnessDomain

public struct SplitTemplate: Sendable, Equatable {
    public let name: String
    public let sessionFocuses: [[MuscleGroup]]
    public var sessionCount: Int { sessionFocuses.count }
    public init(name: String, sessionFocuses: [[MuscleGroup]]) {
        self.name = name
        self.sessionFocuses = sessionFocuses
    }
}

public enum SplitTemplateLibrary {

    public static let fullBody3 = SplitTemplate(
        name: "3-day full body",
        sessionFocuses: Array(repeating: fullBodyFocus, count: 3)
    )

    public static let upperLower4 = SplitTemplate(
        name: "4-day upper / lower",
        sessionFocuses: [upperFocus, lowerFocus, upperFocus, lowerFocus]
    )

    public static let pushPullLegs6 = SplitTemplate(
        name: "6-day push / pull / legs",
        sessionFocuses: [pushFocus, pullFocus, legsFocus, pushFocus, pullFocus, legsFocus]
    )

    public static let all: [SplitTemplate] = [fullBody3, upperLower4, pushPullLegs6]

    private static let fullBodyFocus: [MuscleGroup] =
        [.quads, .hamstrings, .glutes, .chest, .back, .shoulders, .biceps, .triceps, .abs]
    private static let upperFocus: [MuscleGroup] =
        [.chest, .back, .shoulders, .biceps, .triceps]
    private static let lowerFocus: [MuscleGroup] =
        [.quads, .hamstrings, .glutes, .calves, .abs]
    private static let pushFocus: [MuscleGroup] = [.chest, .shoulders, .triceps]
    private static let pullFocus: [MuscleGroup] = [.back, .biceps, .traps]
    private static let legsFocus: [MuscleGroup] = [.quads, .hamstrings, .glutes, .calves]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd FitnessCore && swift test --filter SplitTemplateTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add FitnessCore
git commit -m "Add RuleEngine split template library"
```

---

## Task 10: RuleEngine — TemplateSelector

**Files:**
- Create: `FitnessCore/Sources/RuleEngine/TemplateSelector.swift`
- Test: `FitnessCore/Tests/RuleEngineTests/TemplateSelectorTests.swift`

**Interfaces:**
- Consumes: `ExperienceLevel` (Task 2), `SplitTemplate` + `SplitTemplateLibrary` (Task 9)
- Produces:
  - `enum TemplateSelector { static func select(sessionsPerWeek: Int, experience: ExperienceLevel) -> SplitTemplate }`

**Selection rules (exact):**
- `experience == .beginner`: `sessionsPerWeek <= 3` → `fullBody3`; else → `upperLower4`
- `experience == .intermediate || .advanced`: `sessionsPerWeek <= 3` → `fullBody3`; `== 4` → `upperLower4`; `>= 5` → `pushPullLegs6`

- [ ] **Step 1: Write the failing test**

`TemplateSelectorTests.swift`:
```swift
import Testing
import FitnessDomain
@testable import RuleEngine

@Test func beginnerCapsAtUpperLower() {
    #expect(TemplateSelector.select(sessionsPerWeek: 6, experience: .beginner).name
            == SplitTemplateLibrary.upperLower4.name)
    #expect(TemplateSelector.select(sessionsPerWeek: 2, experience: .beginner).name
            == SplitTemplateLibrary.fullBody3.name)
}

@Test func intermediateGetsPPLAtFivePlus() {
    #expect(TemplateSelector.select(sessionsPerWeek: 5, experience: .intermediate).name
            == SplitTemplateLibrary.pushPullLegs6.name)
    #expect(TemplateSelector.select(sessionsPerWeek: 4, experience: .advanced).name
            == SplitTemplateLibrary.upperLower4.name)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd FitnessCore && swift test --filter TemplateSelectorTests`
Expected: FAIL — `TemplateSelector` not in scope.

- [ ] **Step 3: Write `TemplateSelector.swift`**

```swift
import FitnessDomain

public enum TemplateSelector {

    public static func select(sessionsPerWeek: Int,
                              experience: ExperienceLevel) -> SplitTemplate {
        switch experience {
        case .beginner:
            return sessionsPerWeek <= 3
                ? SplitTemplateLibrary.fullBody3
                : SplitTemplateLibrary.upperLower4
        case .intermediate, .advanced:
            if sessionsPerWeek <= 3 { return SplitTemplateLibrary.fullBody3 }
            if sessionsPerWeek == 4 { return SplitTemplateLibrary.upperLower4 }
            return SplitTemplateLibrary.pushPullLegs6
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd FitnessCore && swift test --filter TemplateSelectorTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add FitnessCore
git commit -m "Add RuleEngine template selector"
```

---

## Task 11: RuleEngine — RulePlanBuilder

**Files:**
- Create: `FitnessCore/Sources/RuleEngine/RulePlanBuilder.swift`
- Test: `FitnessCore/Tests/RuleEngineTests/RulePlanBuilderTests.swift`

**Interfaces:**
- Consumes: `UserContext`, `WeeklyPlan`, `PlannedSession`, `PlannedItem`, `RepRange`, `MuscleVolumeTarget`, `PlanSource`, `MuscleGroup`, `Goal`, `Mechanic` (Domain); `CatalogStore`, `Exercise` (Catalog); `VolumeLandmarks`, `VolumeBand` (Task 8); `SplitTemplate` (Task 9); `TemplateSelector` (Task 10)
- Produces:
  - `struct RulePlanBuilder: Sendable`
    - `init(catalog: CatalogStore)`
    - `func build(context: UserContext, weekStartDate: Date) -> WeeklyPlan`

**Algorithm (deterministic — implement exactly):**

1. `template = TemplateSelector.select(sessionsPerWeek: context.sessionsPerWeek, experience: context.experience)`.
2. `sessionCount = min(template.sessionCount, max(1, context.sessionsPerWeek))`.
3. `activeFocuses = Array(template.sessionFocuses.prefix(sessionCount))`.
4. **Weekly target per muscle:** for every `MuscleGroup` that appears in any `activeFocuses` entry and is **not** in `context.excludedMuscles`: `targetSets = VolumeLandmarks.band(for: muscle, experience: context.experience).mav`. Collect as `[MuscleVolumeTarget]`, ordered by `MuscleGroup.allCases` order.
5. **Sessions to muscle count:** for each such muscle, `sessionsTrainingIt = number of activeFocuses entries containing it`. `setsPerSession = Int((Double(targetSets) / Double(sessionsTrainingIt)).rounded())`, clamped to `>= 2`.
6. **Per session, per focus muscle (skip excluded muscles):**
   - `candidates = catalog.exercises(primaryMuscle: muscle, availableEquipment: context.availableEquipment)` minus any whose `id ∈ context.excludedExerciseIDs`.
   - If `candidates` is empty → skip this muscle for this session (it simply gets less volume; acceptable in P1a).
   - `exercisesForMuscle = min(2, max(1, setsPerSession / 3))` — 1 exercise if `setsPerSession < 6`, else 2.
   - Pick the first `exercisesForMuscle` candidates (already sorted by name → deterministic).
   - `setsEach = Int((Double(setsPerSession) / Double(exercisesForMuscle)).rounded())`, clamped `>= 2`.
   - `reps = repRange(for: context.goal)`.
   - `rest = exercise.mechanic == .compound ? 150 : 75`.
   - `coachNote = "Target \(reps.min)–\(reps.max) reps. Stop 1–2 reps short of failure."`
   - Append `PlannedItem(exerciseID: exercise.id, targetSets: setsEach, targetReps: reps, targetLoadKg: nil, restSeconds: rest, coachNote: coachNote)`.
7. **Session assembly:** `PlannedSession(id: UUID(), order: i, focusMuscles: activeFocuses[i] filtered to non-excluded, items: itemsBuiltAbove)`. Keep the session even if `items` is empty.
8. `rationale = "\(template.name) — matches \(sessionCount) session(s)/week and \(context.experience.rawValue) experience."`
9. Return `WeeklyPlan(weekStartDate:, source: .ruleEngine, rationale:, sessions:, weeklyVolumeTargets:)`.

**`repRange(for:)` (exact):**
- `.getStronger` → `RepRange(min: 4, max: 6)`
- `.buildMuscle` → `RepRange(min: 8, max: 12)`
- `.loseFat`, `.generalFitness` → `RepRange(min: 10, max: 15)`

> **Determinism note for tests:** `PlannedSession.id` is a fresh `UUID()`, so compare plans field-by-field excluding `id`, or inject nothing and just assert on structure/counts as the tests below do.

- [ ] **Step 1: Write the failing test**

`RulePlanBuilderTests.swift`:
```swift
import Testing
import Foundation
import FitnessDomain
import ExerciseCatalog
@testable import RuleEngine

private func testCatalog() -> CatalogStore {
    func ex(_ id: String, _ name: String, _ m: MuscleGroup, _ eq: Equipment, _ mech: Mechanic) -> Exercise {
        Exercise(id: id, name: name, primaryMuscle: m, secondaryMuscles: [], equipment: eq,
                 mechanic: mech, force: nil, difficulty: .beginner, isUnilateral: false,
                 instructions: [], imagePaths: [])
    }
    return CatalogStore(exercises: [
        ex("BB_Bench", "Barbell Bench Press", .chest, .barbell, .compound),
        ex("DB_Press", "Dumbbell Bench Press", .chest, .dumbbell, .compound),
        ex("BB_Row", "Barbell Row", .back, .barbell, .compound),
        ex("BB_Squat", "Barbell Squat", .quads, .barbell, .compound),
        ex("Leg_Curl", "Lying Leg Curl", .hamstrings, .machine, .isolation),
        ex("Hip_Thrust", "Barbell Hip Thrust", .glutes, .barbell, .compound),
        ex("OHP", "Overhead Press", .shoulders, .barbell, .compound),
        ex("Curl", "Barbell Curl", .biceps, .barbell, .isolation),
        ex("Pushdown", "Triceps Pushdown", .triceps, .cable, .isolation),
        ex("Crunch", "Cable Crunch", .abs, .cable, .isolation),
        ex("Calf_Raise", "Standing Calf Raise", .calves, .machine, .isolation),
    ])
}

private func fullEquipmentContext(sessions: Int, goal: Goal = .buildMuscle,
                                  excludedIDs: Set<String> = [],
                                  excludedMuscles: Set<MuscleGroup> = []) -> UserContext {
    UserContext(goal: goal, experience: .intermediate, sessionsPerWeek: sessions,
                sessionLengthMinutes: 60,
                availableEquipment: [.barbell, .dumbbell, .cable, .machine, .bodyweight],
                excludedExerciseIDs: excludedIDs, excludedMuscles: excludedMuscles)
}

@Test func buildsOneSessionPerRequestedDayUpToTemplate() {
    let builder = RulePlanBuilder(catalog: testCatalog())
    let plan = builder.build(context: fullEquipmentContext(sessions: 4), weekStartDate: .init())
    #expect(plan.sessions.count == 4)
    #expect(plan.source == .ruleEngine)
    #expect(plan.sessions.allSatisfy { !$0.items.isEmpty })
}

@Test func neverPrescribesExcludedExerciseOrMuscle() {
    let builder = RulePlanBuilder(catalog: testCatalog())
    let ctx = fullEquipmentContext(sessions: 3, excludedIDs: ["BB_Bench"], excludedMuscles: [.calves])
    let plan = builder.build(context: ctx, weekStartDate: .init())
    let allIDs = plan.sessions.flatMap { $0.items.map(\.exerciseID) }
    #expect(!allIDs.contains("BB_Bench"))
    #expect(!plan.weeklyVolumeTargets.contains { $0.muscle == .calves })
    #expect(!plan.sessions.contains { $0.focusMuscles.contains(.calves) })
}

@Test func weeklyVolumeTargetsUseMAV() {
    let builder = RulePlanBuilder(catalog: testCatalog())
    let plan = builder.build(context: fullEquipmentContext(sessions: 4), weekStartDate: .init())
    let chest = plan.weeklyVolumeTargets.first { $0.muscle == .chest }
    #expect(chest?.targetSets == VolumeLandmarks.band(for: .chest, experience: .intermediate).mav)
}

@Test func repRangeFollowsGoal() {
    let builder = RulePlanBuilder(catalog: testCatalog())
    let plan = builder.build(context: fullEquipmentContext(sessions: 3, goal: .getStronger),
                             weekStartDate: .init())
    let anyItem = plan.sessions.flatMap(\.items).first
    #expect(anyItem?.targetReps == RepRange(min: 4, max: 6))
}

@Test func isDeterministic() {
    let builder = RulePlanBuilder(catalog: testCatalog())
    let ctx = fullEquipmentContext(sessions: 4)
    let a = builder.build(context: ctx, weekStartDate: .init(timeIntervalSince1970: 0))
    let b = builder.build(context: ctx, weekStartDate: .init(timeIntervalSince1970: 0))
    #expect(a.sessions.map { $0.items } == b.sessions.map { $0.items })
    #expect(a.rationale == b.rationale)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd FitnessCore && swift test --filter RulePlanBuilderTests`
Expected: FAIL — `RulePlanBuilder` not in scope.

- [ ] **Step 3: Write `RulePlanBuilder.swift`**

```swift
import Foundation
import FitnessDomain
import ExerciseCatalog

public struct RulePlanBuilder: Sendable {
    private let catalog: CatalogStore

    public init(catalog: CatalogStore) {
        self.catalog = catalog
    }

    public func build(context: UserContext, weekStartDate: Date) -> WeeklyPlan {
        let template = TemplateSelector.select(sessionsPerWeek: context.sessionsPerWeek,
                                               experience: context.experience)
        let sessionCount = min(template.sessionCount, max(1, context.sessionsPerWeek))
        let activeFocuses = Array(template.sessionFocuses.prefix(sessionCount))

        // Step 4 — muscles in scope, ordered by the canonical enum order.
        let focusMuscleSet = Set(activeFocuses.flatMap { $0 })
            .subtracting(context.excludedMuscles)
        let scopedMuscles = MuscleGroup.allCases.filter { focusMuscleSet.contains($0) }

        let weeklyTargets: [MuscleVolumeTarget] = scopedMuscles.map { muscle in
            let mav = VolumeLandmarks.band(for: muscle, experience: context.experience).mav
            return MuscleVolumeTarget(muscle: muscle, targetSets: mav)
        }
        let targetByMuscle = Dictionary(uniqueKeysWithValues: weeklyTargets.map { ($0.muscle, $0.targetSets) })

        let sessionsTrainingMuscle: [MuscleGroup: Int] = scopedMuscles.reduce(into: [:]) { acc, muscle in
            acc[muscle] = activeFocuses.filter { $0.contains(muscle) }.count
        }

        let reps = Self.repRange(for: context.goal)

        var sessions: [PlannedSession] = []
        for (index, focus) in activeFocuses.enumerated() {
            let sessionMuscles = focus.filter { focusMuscleSet.contains($0) }
            var items: [PlannedItem] = []

            for muscle in sessionMuscles {
                guard let target = targetByMuscle[muscle],
                      let trainingCount = sessionsTrainingMuscle[muscle], trainingCount > 0 else { continue }

                let setsPerSession = max(2, Int((Double(target) / Double(trainingCount)).rounded()))

                var candidates = catalog.exercises(primaryMuscle: muscle,
                                                   availableEquipment: context.availableEquipment)
                candidates.removeAll { context.excludedExerciseIDs.contains($0.id) }
                guard !candidates.isEmpty else { continue }

                let exerciseCount = setsPerSession < 6 ? 1 : min(2, candidates.count)
                let setsEach = max(2, Int((Double(setsPerSession) / Double(exerciseCount)).rounded()))

                for exercise in candidates.prefix(exerciseCount) {
                    let rest = exercise.mechanic == .compound ? 150 : 75
                    let note = "Target \(reps.min)–\(reps.max) reps. Stop 1–2 reps short of failure."
                    items.append(PlannedItem(exerciseID: exercise.id,
                                             targetSets: setsEach,
                                             targetReps: reps,
                                             targetLoadKg: nil,
                                             restSeconds: rest,
                                             coachNote: note))
                }
            }

            sessions.append(PlannedSession(id: UUID(), order: index,
                                           focusMuscles: sessionMuscles, items: items))
        }

        let rationale = "\(template.name) — matches \(sessionCount) session(s)/week and \(context.experience.rawValue) experience."
        return WeeklyPlan(weekStartDate: weekStartDate, source: .ruleEngine,
                          rationale: rationale, sessions: sessions,
                          weeklyVolumeTargets: weeklyTargets)
    }

    static func repRange(for goal: Goal) -> RepRange {
        switch goal {
        case .getStronger:                 return RepRange(min: 4, max: 6)
        case .buildMuscle:                 return RepRange(min: 8, max: 12)
        case .loseFat, .generalFitness:    return RepRange(min: 10, max: 15)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd FitnessCore && swift test --filter RulePlanBuilderTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add FitnessCore
git commit -m "Add RuleEngine deterministic plan builder"
```

---

## Task 12: PlanValidation — PlanValidator

**Files:**
- Create: `FitnessCore/Sources/PlanValidation/PlanValidator.swift`
- Delete: `FitnessCore/Sources/PlanValidation/Placeholder.swift`
- Test: `FitnessCore/Tests/PlanValidationTests/PlanValidatorTests.swift`

**Interfaces:**
- Consumes: `WeeklyPlan`, `PlannedSession`, `PlannedItem`, `UserContext`, `MuscleGroup` (Domain); `CatalogStore` (Catalog); `VolumeLandmarks`, `VolumeBand` (RuleEngine)
- Produces:
  - `enum ValidationIssue: Sendable, Equatable`
    - `case unknownExerciseID(String)`
    - `case excludedExercisePresent(String)`
    - `case excludedMusclePresent(MuscleGroup)`
    - `case weeklyVolumeOutOfBand(muscle: MuscleGroup, actualSets: Int, band: VolumeBand)`
    - `case emptySession(order: Int)`
  - `struct PlanValidator: Sendable`
    - `init(catalog: CatalogStore)`
    - `func validate(_ plan: WeeklyPlan, context: UserContext) -> [ValidationIssue]` — empty array ⇒ valid

**Check order (deterministic — emit issues in this order):**
1. For each session in `order`, for each item: if `!catalog.contains(id:)` → `.unknownExerciseID(id)`.
2. Same iteration: if `context.excludedExerciseIDs.contains(id)` → `.excludedExercisePresent(id)`.
3. Same iteration: if the exercise resolves in the catalog and its `primaryMuscle ∈ context.excludedMuscles` → `.excludedMusclePresent(muscle)` (emit once per distinct muscle).
4. **Volume:** for each muscle appearing as a `primaryMuscle` of any *resolvable* planned item, sum `targetSets` across the whole plan. Look up `band = VolumeLandmarks.band(for: muscle, experience: context.experience)`. If `actual < band.mev || actual > band.mrv` → `.weeklyVolumeOutOfBand(muscle:, actualSets:, band:)`. Iterate muscles in `MuscleGroup.allCases` order.
5. For each session with `items.isEmpty` → `.emptySession(order:)`.

- [ ] **Step 1: Write the failing test**

`PlanValidatorTests.swift`:
```swift
import Testing
import Foundation
import FitnessDomain
import ExerciseCatalog
import RuleEngine
@testable import PlanValidation

private func catalog() -> CatalogStore {
    CatalogStore(exercises: [
        Exercise(id: "BB_Bench", name: "Barbell Bench Press", primaryMuscle: .chest,
                 secondaryMuscles: [], equipment: .barbell, mechanic: .compound, force: .push,
                 difficulty: .beginner, isUnilateral: false, instructions: [], imagePaths: [])
    ])
}

private func item(_ id: String, sets: Int) -> PlannedItem {
    PlannedItem(exerciseID: id, targetSets: sets, targetReps: RepRange(min: 8, max: 12),
                targetLoadKg: nil, restSeconds: 150, coachNote: "")
}

private func plan(_ items: [PlannedItem], targets: [MuscleVolumeTarget] = []) -> WeeklyPlan {
    WeeklyPlan(weekStartDate: .init(), source: .ai, rationale: "",
               sessions: [PlannedSession(id: UUID(), order: 0, focusMuscles: [.chest], items: items)],
               weeklyVolumeTargets: targets)
}

private func ctx(excludedIDs: Set<String> = [], excludedMuscles: Set<MuscleGroup> = []) -> UserContext {
    UserContext(goal: .buildMuscle, experience: .intermediate, sessionsPerWeek: 3,
                sessionLengthMinutes: 60, availableEquipment: [.barbell],
                excludedExerciseIDs: excludedIDs, excludedMuscles: excludedMuscles)
}

@Test func validPlanReturnsNoIssues() {
    // chest intermediate band is 8...22; 12 sets is inside.
    let v = PlanValidator(catalog: catalog())
    let issues = v.validate(plan([item("BB_Bench", sets: 12)]), context: ctx())
    #expect(issues.isEmpty)
}

@Test func flagsUnknownExerciseID() {
    let v = PlanValidator(catalog: catalog())
    let issues = v.validate(plan([item("Ghost_Lift", sets: 12)]), context: ctx())
    #expect(issues.contains(.unknownExerciseID("Ghost_Lift")))
}

@Test func flagsExcludedExercise() {
    let v = PlanValidator(catalog: catalog())
    let issues = v.validate(plan([item("BB_Bench", sets: 12)]),
                            context: ctx(excludedIDs: ["BB_Bench"]))
    #expect(issues.contains(.excludedExercisePresent("BB_Bench")))
}

@Test func flagsExcludedMuscle() {
    let v = PlanValidator(catalog: catalog())
    let issues = v.validate(plan([item("BB_Bench", sets: 12)]),
                            context: ctx(excludedMuscles: [.chest]))
    #expect(issues.contains(.excludedMusclePresent(.chest)))
}

@Test func flagsVolumeAboveMRV() {
    let v = PlanValidator(catalog: catalog())
    let issues = v.validate(plan([item("BB_Bench", sets: 40)]), context: ctx())
    let band = VolumeLandmarks.band(for: .chest, experience: .intermediate)
    #expect(issues.contains(.weeklyVolumeOutOfBand(muscle: .chest, actualSets: 40, band: band)))
}

@Test func flagsEmptySession() {
    let v = PlanValidator(catalog: catalog())
    let issues = v.validate(plan([]), context: ctx())
    #expect(issues.contains(.emptySession(order: 0)))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd FitnessCore && swift test --filter PlanValidatorTests`
Expected: FAIL — `PlanValidator` not in scope.

- [ ] **Step 3: Write `PlanValidator.swift`**

```swift
import FitnessDomain
import ExerciseCatalog
import RuleEngine

public enum ValidationIssue: Sendable, Equatable {
    case unknownExerciseID(String)
    case excludedExercisePresent(String)
    case excludedMusclePresent(MuscleGroup)
    case weeklyVolumeOutOfBand(muscle: MuscleGroup, actualSets: Int, band: VolumeBand)
    case emptySession(order: Int)
}

public struct PlanValidator: Sendable {
    private let catalog: CatalogStore

    public init(catalog: CatalogStore) {
        self.catalog = catalog
    }

    public func validate(_ plan: WeeklyPlan, context: UserContext) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        var flaggedExcludedMuscles: Set<MuscleGroup> = []

        let orderedSessions = plan.sessions.sorted { $0.order < $1.order }

        for session in orderedSessions {
            for item in session.items {
                let resolved = catalog.exercise(id: item.exerciseID)

                if resolved == nil {
                    issues.append(.unknownExerciseID(item.exerciseID))
                }
                if context.excludedExerciseIDs.contains(item.exerciseID) {
                    issues.append(.excludedExercisePresent(item.exerciseID))
                }
                if let muscle = resolved?.primaryMuscle,
                   context.excludedMuscles.contains(muscle),
                   !flaggedExcludedMuscles.contains(muscle) {
                    flaggedExcludedMuscles.insert(muscle)
                    issues.append(.excludedMusclePresent(muscle))
                }
            }
        }

        // Volume per resolvable primary muscle, summed across the plan.
        var setsByMuscle: [MuscleGroup: Int] = [:]
        for session in orderedSessions {
            for item in session.items {
                guard let muscle = catalog.exercise(id: item.exerciseID)?.primaryMuscle else { continue }
                setsByMuscle[muscle, default: 0] += item.targetSets
            }
        }
        for muscle in MuscleGroup.allCases {
            guard let actual = setsByMuscle[muscle] else { continue }
            let band = VolumeLandmarks.band(for: muscle, experience: context.experience)
            if actual < band.mev || actual > band.mrv {
                issues.append(.weeklyVolumeOutOfBand(muscle: muscle, actualSets: actual, band: band))
            }
        }

        for session in orderedSessions where session.items.isEmpty {
            issues.append(.emptySession(order: session.order))
        }

        return issues
    }
}
```

Then delete `Placeholder.swift`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd FitnessCore && swift test --filter PlanValidatorTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add FitnessCore
git commit -m "Add PlanValidation plan validator"
```

---

## Task 13: LLMKit — provider protocol and DTOs

**Files:**
- Create: `FitnessCore/Sources/LLMKit/LLMSchema.swift`
- Create: `FitnessCore/Sources/LLMKit/LLMResult.swift`
- Create: `FitnessCore/Sources/LLMKit/LLMError.swift`
- Create: `FitnessCore/Sources/LLMKit/LLMProvider.swift`
- Delete: `FitnessCore/Sources/LLMKit/Placeholder.swift`
- Test: `FitnessCore/Tests/LLMKitTests/LLMKitTypesTests.swift`

**Interfaces:**
- Consumes: nothing from other modules (Foundation only)
- Produces:
  - `struct JSONSchema: Sendable, Equatable { let json: String; init(json: String) }`
  - `struct ImagePayload: Sendable, Equatable { let data: Data; let mimeType: String; init(data: Data, mimeType: String) }`
  - `enum LLMCallType: String, Codable, Sendable, CaseIterable { case weeklyPlan, adjust, finalize, swap, feedback, inbody }`
  - `struct LLMResult<Value: Decodable & Sendable>: Sendable { let value: Value; let inputTokens: Int; let outputTokens: Int; let cachedTokens: Int; let rawJSON: String; init(...) }`
  - `enum LLMError: Error, Sendable, Equatable { case visionUnsupported, emptyResponse, rateLimited, transport(String), decoding(String) }`
  - `protocol LLMProvider: Sendable` with `complete(system:user:schema:as:)` and `completeWithImage(system:user:image:schema:as:)`, both `async throws -> LLMResult<Value>` where `Value: Decodable & Sendable`

> This task ships **no adapter and no networking** — only the contract. Concrete adapters (`openAICompatible`, `gemini`, `anthropic`, `appleOnDevice`) are Phase 1c, in the app target.

- [ ] **Step 1: Write the failing test**

`LLMKitTypesTests.swift`:
```swift
import Testing
import Foundation
@testable import LLMKit

private struct Dummy: Decodable, Sendable, Equatable { let ok: Bool }

private struct StubProvider: LLMProvider {
    func complete<Value: Decodable & Sendable>(system: String, user: String,
                                               schema: JSONSchema,
                                               as type: Value.Type) async throws -> LLMResult<Value> {
        let data = #"{"ok":true}"#.data(using: .utf8)!
        let value = try JSONDecoder().decode(Value.self, from: data)
        return LLMResult(value: value, inputTokens: 10, outputTokens: 2, cachedTokens: 0,
                         rawJSON: #"{"ok":true}"#)
    }
    func completeWithImage<Value: Decodable & Sendable>(system: String, user: String,
                                                        image: ImagePayload, schema: JSONSchema,
                                                        as type: Value.Type) async throws -> LLMResult<Value> {
        throw LLMError.visionUnsupported
    }
}

@Test func callTypeHasSixCases() {
    #expect(LLMCallType.allCases.count == 6)
}

@Test func stubProviderRoundTrips() async throws {
    let result: LLMResult<Dummy> = try await StubProvider()
        .complete(system: "s", user: "u", schema: JSONSchema(json: "{}"), as: Dummy.self)
    #expect(result.value == Dummy(ok: true))
    #expect(result.inputTokens == 10)
}

@Test func visionCallThrowsUnsupported() async {
    await #expect(throws: LLMError.visionUnsupported) {
        let _: LLMResult<Dummy> = try await StubProvider()
            .completeWithImage(system: "s", user: "u",
                               image: ImagePayload(data: Data(), mimeType: "image/jpeg"),
                               schema: JSONSchema(json: "{}"), as: Dummy.self)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd FitnessCore && swift test --filter LLMKitTypesTests`
Expected: FAIL — `LLMProvider` / `LLMResult` / `LLMCallType` not in scope.

- [ ] **Step 3: Write the implementation**

`LLMSchema.swift`:
```swift
import Foundation

public struct JSONSchema: Sendable, Equatable {
    public let json: String
    public init(json: String) { self.json = json }
}

public struct ImagePayload: Sendable, Equatable {
    public let data: Data
    public let mimeType: String
    public init(data: Data, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
}
```

`LLMResult.swift`:
```swift
public enum LLMCallType: String, Codable, Sendable, CaseIterable {
    case weeklyPlan, adjust, finalize, swap, feedback, inbody
}

public struct LLMResult<Value: Decodable & Sendable>: Sendable {
    public let value: Value
    public let inputTokens: Int
    public let outputTokens: Int
    public let cachedTokens: Int
    public let rawJSON: String
    public init(value: Value, inputTokens: Int, outputTokens: Int,
                cachedTokens: Int, rawJSON: String) {
        self.value = value
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.rawJSON = rawJSON
    }
}
```

`LLMError.swift`:
```swift
public enum LLMError: Error, Sendable, Equatable {
    case visionUnsupported
    case emptyResponse
    case rateLimited
    case transport(String)
    case decoding(String)
}
```

`LLMProvider.swift`:
```swift
public protocol LLMProvider: Sendable {
    func complete<Value: Decodable & Sendable>(
        system: String,
        user: String,
        schema: JSONSchema,
        as type: Value.Type
    ) async throws -> LLMResult<Value>

    func completeWithImage<Value: Decodable & Sendable>(
        system: String,
        user: String,
        image: ImagePayload,
        schema: JSONSchema,
        as type: Value.Type
    ) async throws -> LLMResult<Value>
}
```

Then delete `Placeholder.swift`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd FitnessCore && swift test --filter LLMKitTypesTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add FitnessCore
git commit -m "Add LLMKit provider protocol and DTOs"
```

---

## Task 14: Full-suite green + package README

**Files:**
- Create: `FitnessCore/README.md`
- Test: whole suite

**Interfaces:**
- Consumes: everything
- Produces: nothing new — this is the milestone gate

- [ ] **Step 1: Run the whole suite**

Run: `cd FitnessCore && swift test`
Expected: PASS — all test targets, ~30 tests, zero warnings. If there are concurrency or `Sendable` warnings, fix them now (they are errors in language mode v6 for public API).

- [ ] **Step 2: Write `FitnessCore/README.md`**

```markdown
# FitnessCore

Pure Swift package behind the fitness-tracker app. No SwiftUI / UIKit / SwiftData.
Builds and tests with `swift test`.

## Modules

| Module | Responsibility |
|--------|----------------|
| `FitnessDomain` | Value types: `Goal`, `ExperienceLevel`, `MuscleGroup`, `Equipment`, `UserContext`, `WeeklyPlan` + children |
| `ExerciseCatalog` | `Exercise`, `FreeExerciseDBMapper` (free-exercise-db → `Exercise`), `CatalogStore` (load / index / query) |
| `RuleEngine` | `VolumeLandmarks` (MEV/MAV/MRV table), `SplitTemplateLibrary`, `TemplateSelector`, `RulePlanBuilder` (deterministic rule-only plan) |
| `PlanValidation` | `PlanValidator` → `[ValidationIssue]` (unknown id, excluded exercise/muscle, volume out of band, empty session) |
| `LLMKit` | `LLMProvider` protocol + `LLMResult` / `LLMError` / `JSONSchema` / `ImagePayload` / `LLMCallType`. No networking — adapters live in the app target (Phase 1c). |

## Dependency line

`FitnessDomain` ← `ExerciseCatalog` ← `RuleEngine` ← `PlanValidation`
`FitnessDomain` ← `LLMKit`

## Numbers are seeds

Volume landmarks and rep ranges are starting values (spec `docs/06-decisions.md` C6),
tuned later from real training logs.
```

- [ ] **Step 3: Commit**

```bash
git add FitnessCore
git commit -m "Add FitnessCore README and confirm full suite green"
```

---

## Self-Review

**1. Spec coverage:**

| Spec item | Task |
|-----------|------|
| `docs/03` §3 `WeeklyPlan` / `PlannedSession` / `PlannedItem` shapes | 3 |
| `docs/03` §3 `Exercise` shape | 5 |
| `docs/03` §4 base dataset = free-exercise-db, remap to app schema | 6, 7 |
| `docs/03` §4 `CatalogStore` indexes by id / muscle / equipment | 7 |
| `docs/03` §4 "AI may only prescribe catalog ids" (enforcement side) | 12 |
| `docs/03` §5 split templates (full body, upper/lower, PPL) | 9 |
| `docs/03` §5 volume landmarks per muscle × experience | 8 |
| `docs/03` §5 rule-engine plan build (progression stubbed) | 11 |
| `docs/03` §6 `LLMProvider` (`complete` + `completeWithImage`), `LLMResult` w/ cached tokens, `LLMCallType` | 13 |
| `docs/03` §7 validation checks: catalog-id, exclusions, volume band, (empty session added) | 12 |
| `docs/03` §10 Xcode app + UI-free `FitnessCore` package, fast tests | 1, all |
| `docs/06` A10 module names / package location | 1 |
| `docs/06` C6 landmarks seeded from RP, stored as config | 8 |
| `docs/06` C7 templates: full body, upper/lower, PPL, Arnold | 9 — **note: Arnold split deferred (see gaps)** |

**Gaps / deferred (intentional, documented here):**
- **Arnold split** (C7) — `SplitTemplateLibrary` ships 3 of the 4 named templates; Arnold adds no new capability for Phase 1a and can be appended in one task later. Flag for the 1a review.
- **Rest-gap check** and **per-session load-cap check** (`docs/03` §7 items 3 & 5) — need history / multi-session context that arrives in Phase 2–3; not in the 1a validator. Correct per `docs/04` (Phase 1 validator = "catalog-id + exclusion + volume-band checks").
- **Progression rule** — stubbed (no history in 1a), per `docs/04` Phase 1.
- **`SwapSearch`** — Phase 3.
- **Catalog JSON resource + `~100–150` curation** — the bundled `catalog.json` file and its curation ship with the app target in Phase 1b (`CatalogStore.load(fromJSONData:)` is dataset-agnostic and already tested here).

**2. Placeholder scan:** No `TBD` / `TODO` / "add error handling" / prose-only steps. Every code step has complete code. ✅

**3. Type consistency:**
- `CatalogStore.exercises(primaryMuscle:availableEquipment:)` — same label used in Tasks 7, 11, 12. ✅
- `VolumeLandmarks.band(for:experience:)` — Tasks 8, 11, 12. ✅
- `VolumeBand(mev:mav:mrv:)` — Tasks 8, 12. ✅
- `RepRange(min:max:)` — Tasks 3, 11, 12. ✅
- `PlannedItem(exerciseID:targetSets:targetReps:targetLoadKg:restSeconds:coachNote:)` — Tasks 3, 11, 12. ✅
- `WeeklyPlan(weekStartDate:source:rationale:sessions:weeklyVolumeTargets:)` — Tasks 3, 11, 12. ✅
- `LLMResult(value:inputTokens:outputTokens:cachedTokens:rawJSON:)` — Task 13. ✅
- `TemplateSelector.select(sessionsPerWeek:experience:)` — Tasks 10, 11. ✅

---

## Execution Handoff

Choose after review:

**1. Subagent-Driven (recommended)** — fresh subagent per task (1→14), two-stage review between tasks, fast iteration.

**2. Inline Execution** — run tasks in this session via `superpowers:executing-plans`, batched with checkpoints.
