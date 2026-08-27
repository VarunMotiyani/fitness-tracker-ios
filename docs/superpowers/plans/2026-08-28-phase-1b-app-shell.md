# Phase 1b — App Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An installable iOS app that runs onboarding, builds a rule-engine weekly plan from the answers, and shows it in a read-only view — fully offline, no AI. Settings is a scaffold.

**Architecture:** A plain, committed Xcode app project (`FitnessTracker.xcodeproj`) with the `FitnessCore` local Swift package as a dependency. SwiftUI + SwiftData. The app layer is thin: SwiftData `@Model` types persist the onboarding answers and the generated plan (as a Codable blob); a `UserProfile → FitnessCore.UserContext` mapper feeds `RulePlanBuilder` + `PlanValidator`; SwiftUI views render onboarding and the plan. All training logic already lives in `FitnessCore` (Phase 1a) and is not reimplemented here.

**Tech Stack:** Swift 6 / language mode v6, SwiftUI, SwiftData, Xcode 26.6, iOS 26 deployment target, iOS 26.5 simulator. Swift Testing (`import Testing`) — now bundled with Xcode, no package dependency. `FitnessCore` referenced as a local package.

**Spec:** `docs/02-product-design.md` (§1–§4, §9), `docs/03-technical-architecture.md` (§2–§3, §5, §7, §10), `docs/04-roadmap-phases.md` (Phase 1b + the 1a→1b split recorded in `docs/HANDOFF.md`), and `FitnessCore/README.md` ("Known Phase 1b follow-ups").

## Global Constraints

- **Deployment target:** iOS 26.0. Simulator: "iPhone 16" (or any) on the iOS 26.5 runtime.
- **Language mode:** `.v6` (strict concurrency) for the app target and its test target.
- **`FitnessCore` is a local package dependency**, referenced by relative path `../FitnessCore` (or added via Xcode "Add Local…"). Do not copy or vendor its source into the app.
- **No AI in Phase 1b.** No `LLMProvider` implementations, no networking, no `AIClient`, no `PlanCoordinator`. `LLMKit` may be linked (it's a `FitnessCore` product) but nothing calls it. AI integration is Phase 1c.
- **The user drives Xcode.** For every task that needs Xcode's GUI (project creation, adding files/resources, running), the steps are explicit click-by-click and the acceptance check is "builds and runs on the simulator" or a described screenshot. The implementer writes files and gives instructions; a human performs GUI actions and reports back.
- **SwiftData:** one `ModelContainer` created at app launch. Tests use an in-memory container (`ModelConfiguration(isStoredInMemoryOnly: true)`).
- **Catalog for 1b is a stub:** a hand-written `catalog.json` in the free-exercise-db raw shape (so `FitnessCore.CatalogStore.load(fromJSONData:)` consumes it unchanged), ~20 exercises. Full ~120-exercise curation from the real dataset is a later task, out of scope here.
- **No force-unwraps / `try!`** in non-test code. SwiftUI previews may use sample data with `!`.
- **Commit style:** plain imperative subject, no body, **no `Co-Authored-By` trailer**. Do **not** `git push` (the user pushes/PRs manually).
- **Repo layout:** the app lives at `FitnessTracker/` at the repo root, sibling to `FitnessCore/` and `docs/`.

## File Structure

```
fitness-tracker-ios/
├── FitnessCore/                      # Phase 1a package (Task 1 edits Package.swift only)
├── FitnessTracker/                   # NEW — the app
│   ├── FitnessTracker.xcodeproj/
│   ├── FitnessTracker/
│   │   ├── FitnessTrackerApp.swift   # @main, ModelContainer
│   │   ├── RootView.swift            # first-run → Onboarding, else → Plan
│   │   ├── Models/
│   │   │   ├── UserProfile.swift     # @Model + makeUserContext()
│   │   │   └── StoredPlan.swift      # @Model (plan JSON blob)
│   │   ├── Catalog/
│   │   │   ├── catalog.json          # bundled resource (~20 exercises, raw shape)
│   │   │   └── BundledCatalog.swift  # Bundle → CatalogStore
│   │   ├── Planning/
│   │   │   └── PlanService.swift     # profile → UserContext → RulePlanBuilder → PlanValidator
│   │   ├── Features/
│   │   │   ├── Onboarding/
│   │   │   │   ├── OnboardingView.swift        # step container
│   │   │   │   ├── OnboardingModel.swift       # @Observable draft state + completion check
│   │   │   │   └── Steps/                      # Goal, Experience, Body, Schedule, Equipment, Limitations, Review
│   │   │   ├── Plan/
│   │   │   │   └── PlanView.swift              # read-only week → sessions → items
│   │   │   └── Settings/
│   │   │       └── SettingsView.swift          # scaffold: profile summary, start-over, disabled AI section
│   │   └── Assets.xcassets/
│   └── FitnessTrackerTests/
│       ├── BundledCatalogTests.swift
│       ├── UserProfileMappingTests.swift
│       ├── StoredPlanTests.swift
│       ├── PlanServiceTests.swift
│       └── OnboardingModelTests.swift
└── docs/
```

---

## Task 1: Drop the swift-testing package dependency from FitnessCore

**Files:**
- Modify: `FitnessCore/Package.swift`
- Modify: `.gitignore`
- Delete: `FitnessCore/Package.resolved`

**Interfaces:**
- Consumes: nothing
- Produces: a `FitnessCore` package with **zero external dependencies**; `import Testing` resolves against the Xcode-bundled framework.

**Context:** Phase 1a pinned `swiftlang/swift-testing` because the machine had Command Line Tools only. Xcode 26.6 is now installed and active (`xcode-select -p` → `/Applications/Xcode.app/Contents/Developer`), and its toolchain bundles `Testing.framework`. The dependency (and its transitive swift-syntax source build) is no longer needed.

- [ ] **Step 1: Confirm the environment**

Run: `xcode-select -p`
Expected: `/Applications/Xcode.app/Contents/Developer` (NOT `/Library/Developer/CommandLineTools`). If it still shows CommandLineTools, stop and report — Task 1 cannot proceed.

- [ ] **Step 2: Rewrite `FitnessCore/Package.swift` without the dependency**

```swift
// swift-tools-version: 6.2
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

- [ ] **Step 3: Restore the gitignore for `Package.resolved`**

In `.gitignore`, under the "Swift Package Manager" section, the lines are currently:
```
Package.resolved
!FitnessCore/Package.resolved
```
Replace both with just:
```
Package.resolved
```

- [ ] **Step 4: Delete the tracked resolved file**

Run: `git rm FitnessCore/Package.resolved`

- [ ] **Step 5: Verify the suite with bundled Testing**

Run: `cd FitnessCore && rm -rf .build && swift test`
Expected: `Test run with 35 tests passed`, zero warnings. The output should NOT mention resolving `swift-testing` or `swift-syntax`. Build time should be seconds, not minutes.

- [ ] **Step 6: Commit**

```bash
cd /Users/vmotiyani/Documents/person/fitness-tracker-ios
git add FitnessCore/Package.swift .gitignore FitnessCore/Package.resolved
git commit -m "Drop swift-testing package dependency (Xcode bundles Testing)"
```

---

## Task 2: Create the Xcode app project

**Files:**
- Create (via Xcode GUI): `FitnessTracker/FitnessTracker.xcodeproj` and `FitnessTracker/FitnessTracker/` with the default SwiftUI app template
- Modify: `.gitignore` (add Xcode user-state ignores scoped to the app if not already covered — the repo's `.gitignore` already has `xcuserdata/`, `*.xcuserstate`, `DerivedData/`; confirm they cover `FitnessTracker/`)
- Create: `FitnessTracker/FitnessTracker/RootView.swift` (temporary "Hello" content)

**Interfaces:**
- Consumes: the `FitnessCore` package (Task 1)
- Produces: a buildable, runnable iOS app target `FitnessTracker` + a `FitnessTrackerTests` unit test target, both able to `import FitnessCore`'s products.

**This task is Xcode-GUI driven. The implementer writes `RootView.swift` and this instruction list; a human performs the Xcode steps and reports the result.**

- [ ] **Step 1: Create the project**

In Xcode: File → New → Project → iOS → **App**.
- Product Name: `FitnessTracker`
- Organization Identifier: `com.varunmotiyani` (or any reverse-DNS you own)
- Interface: **SwiftUI**
- Language: **Swift**
- Storage: **None** (we add SwiftData manually in Task 4 — the template's SwiftData option scaffolds an `Item` model we don't want)
- Include Tests: **checked**
- Save into: the repo root, so the path is `fitness-tracker-ios/FitnessTracker/`. **Uncheck** "Create Git repository" (the repo already exists).

- [ ] **Step 2: Set the deployment target and language mode**

Select the project → `FitnessTracker` target → General → **Minimum Deployments → iOS 26.0**.
Then Build Settings → search "Swift Language Version" → confirm **Swift 6**. Search "Strict Concurrency Checking" → set to **Complete** for the `FitnessTracker` and `FitnessTrackerTests` targets.

- [ ] **Step 3: Add the local package**

File → Add Package Dependencies… → **Add Local…** → select the `FitnessCore/` folder → Add.
Then project → `FitnessTracker` target → General → **Frameworks, Libraries, and Embedded Content** → `+` → add all five products: `FitnessDomain`, `ExerciseCatalog`, `RuleEngine`, `PlanValidation`, `LLMKit`.

- [ ] **Step 4: Replace the template content view**

Delete the template's `ContentView.swift`. Create `FitnessTracker/FitnessTracker/RootView.swift`:

```swift
import SwiftUI
import FitnessCore

struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("FitnessTracker")
                .font(.largeTitle.bold())
            Text("Phase 1b shell")
                .foregroundStyle(.secondary)
            Text("Catalog types available: \(MuscleGroup.allCases.count) muscle groups")
                .font(.footnote)
        }
        .padding()
    }
}

#Preview { RootView() }
```

Note: `import FitnessCore` is not a real module — replace with the specific product imports used: `import FitnessDomain`. (The umbrella `FitnessCore` name is the *package*, not a module.) Corrected file:

```swift
import SwiftUI
import FitnessDomain

struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("FitnessTracker").font(.largeTitle.bold())
            Text("Phase 1b shell").foregroundStyle(.secondary)
            Text("\(MuscleGroup.allCases.count) muscle groups linked from FitnessCore")
                .font(.footnote)
        }
        .padding()
    }
}

#Preview { RootView() }
```

In `FitnessTrackerApp.swift`, set the root to `RootView()`:
```swift
import SwiftUI

@main
struct FitnessTrackerApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}
```

- [ ] **Step 5: Build and run**

Select the `FitnessTracker` scheme + an "iPhone 16 (iOS 26.5)" simulator. Product → Run (⌘R).
Expected: app launches in the simulator, shows "FitnessTracker / Phase 1b shell / 13 muscle groups linked from FitnessCore".
Also run the empty test target once (⌘U) — it should pass with 0 tests or the template's 1 stub.

- [ ] **Step 6: Commit**

```bash
git add FitnessTracker .gitignore
git commit -m "Add FitnessTracker Xcode app project with FitnessCore linked"
```

Confirm `git status` shows no `xcuserdata/` / `*.xcuserstate` / `DerivedData/` staged (the repo `.gitignore` should already exclude them; if any slipped in, add the pattern and unstage).

---

## Task 3: Bundled stub catalog

**Files:**
- Create: `FitnessTracker/FitnessTracker/Catalog/catalog.json`
- Create: `FitnessTracker/FitnessTracker/Catalog/BundledCatalog.swift`
- Test: `FitnessTracker/FitnessTrackerTests/BundledCatalogTests.swift`
- Xcode: add both files to the `FitnessTracker` target; ensure `catalog.json` is in "Copy Bundle Resources"

**Interfaces:**
- Consumes: `ExerciseCatalog.CatalogStore`, `ExerciseCatalog.CatalogError` (Phase 1a)
- Produces:
  - `enum BundledCatalog { static func load(bundle: Bundle = .main) throws -> CatalogStore }`
  - `enum BundledCatalogError: Error, Equatable { case resourceMissing }`

- [ ] **Step 1: Write `catalog.json` (raw free-exercise-db shape, exactly these 20 entries)**

```json
[
  {"id":"Barbell_Bench_Press","name":"Barbell Bench Press","force":"push","level":"beginner","mechanic":"compound","equipment":"barbell","primaryMuscles":["chest"],"secondaryMuscles":["triceps","shoulders"],"instructions":["Lie flat on a bench, grip the bar slightly wider than shoulder width.","Lower the bar to mid-chest, then press to lockout without bouncing."],"category":"strength","images":[]},
  {"id":"Dumbbell_Bench_Press","name":"Dumbbell Bench Press","force":"push","level":"beginner","mechanic":"compound","equipment":"dumbbell","primaryMuscles":["chest"],"secondaryMuscles":["triceps","shoulders"],"instructions":["Lie on a flat bench holding a dumbbell in each hand at chest level.","Press the dumbbells up until arms are extended, then lower under control."],"category":"strength","images":[]},
  {"id":"Cable_Crossover","name":"Cable Crossover","force":"push","level":"intermediate","mechanic":"isolation","equipment":"cable","primaryMuscles":["chest"],"secondaryMuscles":[],"instructions":["Set both pulleys high and hold a handle in each hand, one foot forward.","Bring the handles together in front of your chest in a hugging arc, then return slowly."],"category":"strength","images":[]},
  {"id":"Barbell_Row","name":"Bent Over Barbell Row","force":"pull","level":"intermediate","mechanic":"compound","equipment":"barbell","primaryMuscles":["middle back"],"secondaryMuscles":["lats","biceps"],"instructions":["Hinge at the hips with a flat back, holding the bar at arms length.","Pull the bar to your lower ribcage, squeeze the shoulder blades, then lower."],"category":"strength","images":[]},
  {"id":"Lat_Pulldown","name":"Wide Grip Lat Pulldown","force":"pull","level":"beginner","mechanic":"compound","equipment":"cable","primaryMuscles":["lats"],"secondaryMuscles":["biceps","middle back"],"instructions":["Sit with thighs under the pads, grip the bar wider than shoulder width.","Pull the bar to your upper chest, leading with the elbows, then return under control."],"category":"strength","images":[]},
  {"id":"Seated_Cable_Row","name":"Seated Cable Row","force":"pull","level":"beginner","mechanic":"compound","equipment":"cable","primaryMuscles":["middle back"],"secondaryMuscles":["lats","biceps"],"instructions":["Sit with feet on the platform and a slight bend in the knees, back straight.","Pull the handle to your abdomen, squeezing the shoulder blades, then extend the arms."],"category":"strength","images":[]},
  {"id":"Barbell_Back_Squat","name":"Barbell Back Squat","force":"push","level":"intermediate","mechanic":"compound","equipment":"barbell","primaryMuscles":["quadriceps"],"secondaryMuscles":["glutes","hamstrings"],"instructions":["Rest the bar on your upper back, feet shoulder width, toes slightly out.","Sit down and back until thighs are at least parallel, then drive up through mid-foot."],"category":"strength","images":[]},
  {"id":"Leg_Press","name":"Leg Press","force":"push","level":"beginner","mechanic":"compound","equipment":"machine","primaryMuscles":["quadriceps"],"secondaryMuscles":["glutes","hamstrings"],"instructions":["Sit in the machine with feet shoulder width on the platform.","Lower the platform until knees reach about 90 degrees, then press back without locking out hard."],"category":"strength","images":[]},
  {"id":"Leg_Extension","name":"Leg Extension","force":"push","level":"beginner","mechanic":"isolation","equipment":"machine","primaryMuscles":["quadriceps"],"secondaryMuscles":[],"instructions":["Sit with the pad on your lower shins and knees aligned with the pivot.","Extend the knees until legs are straight, pause, then lower under control."],"category":"strength","images":[]},
  {"id":"Romanian_Deadlift","name":"Romanian Deadlift","force":"pull","level":"intermediate","mechanic":"compound","equipment":"barbell","primaryMuscles":["hamstrings"],"secondaryMuscles":["glutes","lower back"],"instructions":["Hold the bar at hip height, soft knees, shoulders back.","Push the hips back and lower the bar along your thighs until you feel a hamstring stretch, then stand tall."],"category":"strength","images":[]},
  {"id":"Lying_Leg_Curl","name":"Lying Leg Curl","force":"pull","level":"beginner","mechanic":"isolation","equipment":"machine","primaryMuscles":["hamstrings"],"secondaryMuscles":["calves"],"instructions":["Lie face down with the pad against your lower calves.","Curl your heels toward your glutes, squeeze, then lower slowly."],"category":"strength","images":[]},
  {"id":"Barbell_Hip_Thrust","name":"Barbell Hip Thrust","force":"push","level":"beginner","mechanic":"compound","equipment":"barbell","primaryMuscles":["glutes"],"secondaryMuscles":["hamstrings"],"instructions":["Upper back on a bench, barbell across the hips, feet flat.","Drive through the heels to lift the hips until the torso is parallel to the floor, squeeze, then lower."],"category":"strength","images":[]},
  {"id":"Overhead_Press","name":"Standing Overhead Press","force":"push","level":"intermediate","mechanic":"compound","equipment":"barbell","primaryMuscles":["shoulders"],"secondaryMuscles":["triceps"],"instructions":["Hold the bar at collarbone height, elbows slightly in front, core braced.","Press overhead until arms lock, moving the head back then through, then lower to the start."],"category":"strength","images":[]},
  {"id":"Dumbbell_Lateral_Raise","name":"Dumbbell Lateral Raise","force":"push","level":"beginner","mechanic":"isolation","equipment":"dumbbell","primaryMuscles":["shoulders"],"secondaryMuscles":[],"instructions":["Stand holding a dumbbell in each hand at your sides, slight elbow bend.","Raise the dumbbells out to shoulder height, leading with the elbows, then lower slowly."],"category":"strength","images":[]},
  {"id":"Barbell_Curl","name":"Barbell Curl","force":"pull","level":"beginner","mechanic":"isolation","equipment":"barbell","primaryMuscles":["biceps"],"secondaryMuscles":["forearms"],"instructions":["Stand holding the bar at shoulder width, elbows at your sides.","Curl the bar to shoulder height without swinging, then lower under control."],"category":"strength","images":[]},
  {"id":"Dumbbell_Curl","name":"Alternating Dumbbell Curl","force":"pull","level":"beginner","mechanic":"isolation","equipment":"dumbbell","primaryMuscles":["biceps"],"secondaryMuscles":["forearms"],"instructions":["Stand with a dumbbell in each hand, palms facing in.","Curl one dumbbell, rotating the palm up as you lift, then lower and alternate."],"category":"strength","images":[]},
  {"id":"Triceps_Pushdown","name":"Triceps Pushdown","force":"push","level":"beginner","mechanic":"isolation","equipment":"cable","primaryMuscles":["triceps"],"secondaryMuscles":[],"instructions":["Face a high pulley with a straight or rope attachment, elbows pinned to your sides.","Extend the arms fully down, squeeze the triceps, then return to 90 degrees."],"category":"strength","images":[]},
  {"id":"Lying_Triceps_Extension","name":"Lying Triceps Extension","force":"push","level":"intermediate","mechanic":"isolation","equipment":"barbell","primaryMuscles":["triceps"],"secondaryMuscles":[],"instructions":["Lie on a bench holding an EZ or straight bar over your forehead, upper arms vertical.","Bend the elbows to lower the bar near your hairline, then extend back up."],"category":"strength","images":[]},
  {"id":"Standing_Calf_Raise","name":"Standing Calf Raise","force":"push","level":"beginner","mechanic":"isolation","equipment":"machine","primaryMuscles":["calves"],"secondaryMuscles":[],"instructions":["Stand with the balls of your feet on the platform, shoulders under the pads.","Rise onto your toes as high as possible, pause, then lower until you feel a stretch."],"category":"strength","images":[]},
  {"id":"Cable_Crunch","name":"Cable Crunch","force":"pull","level":"beginner","mechanic":"isolation","equipment":"cable","primaryMuscles":["abdominals"],"secondaryMuscles":[],"instructions":["Kneel facing a high pulley, holding a rope beside your head.","Crunch down by flexing the spine and bringing your elbows toward your thighs, then return slowly."],"category":"strength","images":[]}
]
```

(20 entries. Muscle coverage after `FreeExerciseDBMapper` maps them: chest, back [from lats/middle back], lowerBack, shoulders, biceps, triceps, forearms [secondary only], quads, hamstrings, glutes, calves, abs. `traps` has no entry — acceptable for the stub; `pushPullLegs6`'s pull day includes `.traps` but the builder simply skips a muscle with no candidates.)

- [ ] **Step 2: Write the failing test**

`FitnessTrackerTests/BundledCatalogTests.swift`:
```swift
import Testing
import Foundation
import FitnessDomain
import ExerciseCatalog
@testable import FitnessTracker

@Test func bundledCatalogLoadsAndCoversMajorMuscles() throws {
    let store = try BundledCatalog.load(bundle: Bundle(for: BundledCatalogTestAnchor.self))
    #expect(store.all.count == 20)
    // every major training muscle a template uses has at least one barbell/dumbbell/machine/cable option
    for muscle in [MuscleGroup.chest, .back, .quads, .hamstrings, .glutes, .shoulders, .biceps, .triceps, .calves, .abs] {
        let matches = store.exercises(primaryMuscle: muscle,
                                      availableEquipment: [.barbell, .dumbbell, .machine, .cable])
        #expect(!matches.isEmpty, "no catalog entry for \(muscle)")
    }
}

@Test func bundledCatalogThrowsWhenResourceMissing() {
    #expect(throws: BundledCatalogError.resourceMissing) {
        _ = try BundledCatalog.load(bundle: Bundle(for: BundledCatalogTestAnchor.self), resourceName: "does_not_exist")
    }
}

final class BundledCatalogTestAnchor {}
```

Note: `Bundle(for:)` needs a class defined in the test bundle — `BundledCatalogTestAnchor` serves that. The production default stays `.main`.

- [ ] **Step 3: Run it — expect FAIL**

⌘U (or `xcodebuild test -scheme FitnessTracker -destination 'platform=iOS Simulator,name=iPhone 16'`).
Expected: compile failure — `BundledCatalog` not found.

- [ ] **Step 4: Write `BundledCatalog.swift`**

```swift
import Foundation
import ExerciseCatalog

enum BundledCatalogError: Error, Equatable {
    case resourceMissing
}

enum BundledCatalog {
    static func load(bundle: Bundle = .main, resourceName: String = "catalog") throws -> CatalogStore {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw BundledCatalogError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        return try CatalogStore.load(fromJSONData: data)
    }
}
```

- [ ] **Step 5: Add files to the target**

In Xcode: drag `Catalog/` into the project navigator under `FitnessTracker`. For `catalog.json`, in the File Inspector check **Target Membership → FitnessTracker**, and confirm it appears under Build Phases → Copy Bundle Resources. `BundledCatalog.swift` → Target Membership → FitnessTracker.

- [ ] **Step 6: Run the test — expect PASS**

⌘U. Both `BundledCatalogTests` pass.

- [ ] **Step 7: Commit**

```bash
git add FitnessTracker
git commit -m "Add bundled stub catalog and BundledCatalog loader"
```

---

## Task 4: UserProfile SwiftData model + ModelContainer

**Files:**
- Create: `FitnessTracker/FitnessTracker/Models/UserProfile.swift`
- Modify: `FitnessTracker/FitnessTracker/FitnessTrackerApp.swift`
- Test: `FitnessTracker/FitnessTrackerTests/UserProfileMappingTests.swift` (mapping test added in Task 5; this task adds a persistence round-trip test)
- Test: `FitnessTracker/FitnessTrackerTests/UserProfilePersistenceTests.swift`

**Interfaces:**
- Consumes: SwiftData
- Produces:
  - `@Model final class UserProfile` with stored properties:
    `goalRaw: String`, `experienceRaw: String`, `heightCm: Double`, `weightKg: Double`, `birthYear: Int`, `sexRaw: String`, `sessionsPerWeek: Int`, `sessionLengthMinutes: Int`, `availableEquipmentRaws: [String]`, `excludedMuscleRaws: [String]`, `excludedExerciseIDs: [String]`, `createdAt: Date`, `updatedAt: Date`
  - `init(goalRaw:experienceRaw:heightCm:weightKg:birthYear:sexRaw:sessionsPerWeek:sessionLengthMinutes:availableEquipmentRaws:excludedMuscleRaws:excludedExerciseIDs:)` — sets `createdAt = .now`, `updatedAt = .now`
- Later tasks rely on: reading the single `UserProfile` via `@Query` / `FetchDescriptor`.

- [ ] **Step 1: Write the failing test**

`FitnessTrackerTests/UserProfilePersistenceTests.swift`:
```swift
import Testing
import SwiftData
@testable import FitnessTracker

@MainActor
@Test func userProfileRoundTripsThroughSwiftData() throws {
    let container = try ModelContainer(
        for: UserProfile.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext

    let profile = UserProfile(
        goalRaw: "buildMuscle", experienceRaw: "intermediate",
        heightCm: 178, weightKg: 76, birthYear: 2001, sexRaw: "male",
        sessionsPerWeek: 4, sessionLengthMinutes: 60,
        availableEquipmentRaws: ["barbell", "dumbbell", "cable", "machine"],
        excludedMuscleRaws: [], excludedExerciseIDs: []
    )
    context.insert(profile)
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<UserProfile>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.goalRaw == "buildMuscle")
    #expect(fetched.first?.availableEquipmentRaws.contains("cable") == true)
}
```

- [ ] **Step 2: Run it — expect FAIL** (`UserProfile` not found). ⌘U.

- [ ] **Step 3: Write `UserProfile.swift`**

```swift
import Foundation
import SwiftData

@Model
final class UserProfile {
    var goalRaw: String
    var experienceRaw: String
    var heightCm: Double
    var weightKg: Double
    var birthYear: Int
    var sexRaw: String
    var sessionsPerWeek: Int
    var sessionLengthMinutes: Int
    var availableEquipmentRaws: [String]
    var excludedMuscleRaws: [String]
    var excludedExerciseIDs: [String]
    var createdAt: Date
    var updatedAt: Date

    init(goalRaw: String,
         experienceRaw: String,
         heightCm: Double,
         weightKg: Double,
         birthYear: Int,
         sexRaw: String,
         sessionsPerWeek: Int,
         sessionLengthMinutes: Int,
         availableEquipmentRaws: [String],
         excludedMuscleRaws: [String],
         excludedExerciseIDs: [String]) {
        self.goalRaw = goalRaw
        self.experienceRaw = experienceRaw
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.birthYear = birthYear
        self.sexRaw = sexRaw
        self.sessionsPerWeek = sessionsPerWeek
        self.sessionLengthMinutes = sessionLengthMinutes
        self.availableEquipmentRaws = availableEquipmentRaws
        self.excludedMuscleRaws = excludedMuscleRaws
        self.excludedExerciseIDs = excludedExerciseIDs
        self.createdAt = .now
        self.updatedAt = .now
    }
}
```

- [ ] **Step 4: Wire the container in `FitnessTrackerApp.swift`**

```swift
import SwiftUI
import SwiftData

@main
struct FitnessTrackerApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
            .modelContainer(for: [UserProfile.self, StoredPlan.self])
    }
}
```

Note: `StoredPlan` is created in Task 6. Until then, temporarily use `.modelContainer(for: UserProfile.self)` and update it in Task 6. Add a `// TODO(Task 6): add StoredPlan` comment.

- [ ] **Step 5: Add `UserProfile.swift` to the target** (Xcode: Models group → Target Membership → FitnessTracker).

- [ ] **Step 6: Run the test — expect PASS.** ⌘U.

- [ ] **Step 7: Commit**

```bash
git add FitnessTracker
git commit -m "Add UserProfile SwiftData model and model container"
```

---

## Task 5: UserProfile → UserContext mapping

**Files:**
- Create: `FitnessTracker/FitnessTracker/Models/UserProfile+Mapping.swift`
- Test: `FitnessTracker/FitnessTrackerTests/UserProfileMappingTests.swift`

**Interfaces:**
- Consumes: `UserProfile` (Task 4); `FitnessDomain.UserContext`, `Goal`, `ExperienceLevel`, `Equipment`, `MuscleGroup`
- Produces: `extension UserProfile { func makeUserContext() -> UserContext }`
  - Unknown `goalRaw` → `.generalFitness`; unknown `experienceRaw` → `.beginner`; unmappable equipment/muscle raw strings are dropped (via `compactMap`).

- [ ] **Step 1: Write the failing test**

`FitnessTrackerTests/UserProfileMappingTests.swift`:
```swift
import Testing
import FitnessDomain
@testable import FitnessTracker

private func profile(goal: String = "buildMuscle",
                     experience: String = "intermediate",
                     equipment: [String] = ["barbell", "dumbbell"],
                     excludedMuscles: [String] = [],
                     excludedIDs: [String] = []) -> UserProfile {
    UserProfile(goalRaw: goal, experienceRaw: experience, heightCm: 175, weightKg: 75,
                birthYear: 2000, sexRaw: "male", sessionsPerWeek: 4, sessionLengthMinutes: 60,
                availableEquipmentRaws: equipment, excludedMuscleRaws: excludedMuscles,
                excludedExerciseIDs: excludedIDs)
}

@Test func mapsCleanValues() {
    let ctx = profile().makeUserContext()
    #expect(ctx.goal == .buildMuscle)
    #expect(ctx.experience == .intermediate)
    #expect(ctx.availableEquipment == [.barbell, .dumbbell])
    #expect(ctx.sessionsPerWeek == 4)
}

@Test func unknownEnumRawsFallBack() {
    let ctx = profile(goal: "zzz", experience: "yyy", equipment: ["barbell", "spaceship"]).makeUserContext()
    #expect(ctx.goal == .generalFitness)
    #expect(ctx.experience == .beginner)
    #expect(ctx.availableEquipment == [.barbell])   // "spaceship" dropped
}

@Test func exclusionsCarryThrough() {
    let ctx = profile(excludedMuscles: ["lowerBack"], excludedIDs: ["Romanian_Deadlift"]).makeUserContext()
    #expect(ctx.excludedMuscles == [.lowerBack])
    #expect(ctx.excludedExerciseIDs == ["Romanian_Deadlift"])
}
```

- [ ] **Step 2: Run it — expect FAIL** (`makeUserContext` not found). ⌘U.

- [ ] **Step 3: Write `UserProfile+Mapping.swift`**

```swift
import FitnessDomain

extension UserProfile {
    func makeUserContext() -> UserContext {
        UserContext(
            goal: Goal(rawValue: goalRaw) ?? .generalFitness,
            experience: ExperienceLevel(rawValue: experienceRaw) ?? .beginner,
            sessionsPerWeek: sessionsPerWeek,
            sessionLengthMinutes: sessionLengthMinutes,
            availableEquipment: Set(availableEquipmentRaws.compactMap(Equipment.init(rawValue:))),
            excludedExerciseIDs: Set(excludedExerciseIDs),
            excludedMuscles: Set(excludedMuscleRaws.compactMap(MuscleGroup.init(rawValue:)))
        )
    }
}
```

- [ ] **Step 4: Add to target, run the test — expect PASS.** ⌘U.

- [ ] **Step 5: Commit**

```bash
git add FitnessTracker
git commit -m "Add UserProfile to UserContext mapping"
```

---

## Task 6: StoredPlan SwiftData model

**Files:**
- Create: `FitnessTracker/FitnessTracker/Models/StoredPlan.swift`
- Modify: `FitnessTracker/FitnessTracker/FitnessTrackerApp.swift` (add `StoredPlan.self` to the container)
- Test: `FitnessTracker/FitnessTrackerTests/StoredPlanTests.swift`

**Interfaces:**
- Consumes: SwiftData; `FitnessDomain.WeeklyPlan` (Codable)
- Produces:
  - `@Model final class StoredPlan` with `generatedAt: Date`, `weekStartDate: Date`, `planJSON: Data`, `hadValidationIssues: Bool`
  - `init(plan: WeeklyPlan, hadValidationIssues: Bool) throws` — encodes `plan` to `planJSON` with `JSONEncoder`, sets `generatedAt = .now`, `weekStartDate = plan.weekStartDate`
  - `func decodedPlan() throws -> WeeklyPlan` — `JSONDecoder().decode(WeeklyPlan.self, from: planJSON)`

- [ ] **Step 1: Write the failing test**

`FitnessTrackerTests/StoredPlanTests.swift`:
```swift
import Testing
import Foundation
import SwiftData
import FitnessDomain
@testable import FitnessTracker

private func samplerPlan() -> WeeklyPlan {
    WeeklyPlan(
        weekStartDate: Date(timeIntervalSince1970: 1_700_000_000),
        source: .ruleEngine,
        rationale: "3-day full body",
        sessions: [PlannedSession(id: UUID(), order: 0, focusMuscles: [.chest],
            items: [PlannedItem(exerciseID: "Barbell_Bench_Press", targetSets: 3,
                targetReps: RepRange(min: 8, max: 12), targetLoadKg: nil,
                restSeconds: 150, coachNote: "…")])],
        weeklyVolumeTargets: [MuscleVolumeTarget(muscle: .chest, targetSets: 12)]
    )
}

@MainActor
@Test func storedPlanRoundTripsPlan() throws {
    let container = try ModelContainer(for: StoredPlan.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let original = samplerPlan()
    let stored = try StoredPlan(plan: original, hadValidationIssues: false)
    container.mainContext.insert(stored)
    try container.mainContext.save()

    let fetched = try container.mainContext.fetch(FetchDescriptor<StoredPlan>()).first
    #expect(fetched != nil)
    #expect(try fetched?.decodedPlan() == original)
    #expect(fetched?.hadValidationIssues == false)
}
```

- [ ] **Step 2: Run it — expect FAIL.** ⌘U.

- [ ] **Step 3: Write `StoredPlan.swift`**

```swift
import Foundation
import SwiftData
import FitnessDomain

@Model
final class StoredPlan {
    var generatedAt: Date
    var weekStartDate: Date
    var planJSON: Data
    var hadValidationIssues: Bool

    init(plan: WeeklyPlan, hadValidationIssues: Bool) throws {
        self.generatedAt = .now
        self.weekStartDate = plan.weekStartDate
        self.planJSON = try JSONEncoder().encode(plan)
        self.hadValidationIssues = hadValidationIssues
    }

    func decodedPlan() throws -> WeeklyPlan {
        try JSONDecoder().decode(WeeklyPlan.self, from: planJSON)
    }
}
```

- [ ] **Step 4: Add `StoredPlan.self` to the container**

`FitnessTrackerApp.swift`: `.modelContainer(for: [UserProfile.self, StoredPlan.self])`. Remove the Task 4 TODO comment.

- [ ] **Step 5: Add to target, run the test — expect PASS.** ⌘U.

- [ ] **Step 6: Commit**

```bash
git add FitnessTracker
git commit -m "Add StoredPlan SwiftData model"
```

---

## Task 7: PlanService

**Files:**
- Create: `FitnessTracker/FitnessTracker/Planning/PlanService.swift`
- Test: `FitnessTracker/FitnessTrackerTests/PlanServiceTests.swift`

**Interfaces:**
- Consumes: `UserProfile.makeUserContext()` (Task 5); `ExerciseCatalog.CatalogStore`; `RuleEngine.RulePlanBuilder`; `PlanValidation.PlanValidator`, `PlanValidation.ValidationIssue`; `FitnessDomain.WeeklyPlan`; `BundledCatalog` (Task 3)
- Produces:
  - `struct PlanService { let catalog: CatalogStore; init(catalog: CatalogStore); func generate(for profile: UserProfile, weekStartDate: Date) -> PlanResult }`
  - `struct PlanResult { let plan: WeeklyPlan; let issues: [ValidationIssue] }`
  - `static func live() throws -> PlanService` — builds from `BundledCatalog.load()`

- [ ] **Step 1: Write the failing test**

`FitnessTrackerTests/PlanServiceTests.swift`:
```swift
import Testing
import Foundation
import FitnessDomain
import ExerciseCatalog
@testable import FitnessTracker

private func fullEquipmentProfile(sessions: Int = 4, goal: String = "buildMuscle") -> UserProfile {
    UserProfile(goalRaw: goal, experienceRaw: "intermediate", heightCm: 178, weightKg: 78,
                birthYear: 2000, sexRaw: "male", sessionsPerWeek: sessions, sessionLengthMinutes: 60,
                availableEquipmentRaws: ["barbell", "dumbbell", "cable", "machine", "bodyweight"],
                excludedMuscleRaws: [], excludedExerciseIDs: [])
}

@Test func generatesAValidPlanFromTheStubCatalog() throws {
    let catalog = try BundledCatalog.load(bundle: Bundle(for: BundledCatalogTestAnchor.self))
    let service = PlanService(catalog: catalog)
    let result = service.generate(for: fullEquipmentProfile(), weekStartDate: .init())

    #expect(result.plan.source == .ruleEngine)
    #expect(result.plan.sessions.count == 4)          // upperLower4 for 4 sessions / intermediate
    #expect(result.plan.sessions.allSatisfy { !$0.items.isEmpty })
    // stub catalog covers every focus muscle in upper/lower, so the plan should validate
    #expect(result.issues.isEmpty, "unexpected issues: \(result.issues)")
}

@Test func excludedExerciseNeverAppears() throws {
    let catalog = try BundledCatalog.load(bundle: Bundle(for: BundledCatalogTestAnchor.self))
    var p = fullEquipmentProfile(sessions: 3)
    p.excludedExerciseIDs = ["Barbell_Bench_Press"]
    let result = PlanService(catalog: catalog).generate(for: p, weekStartDate: .init())
    let ids = result.plan.sessions.flatMap { $0.items.map(\.exerciseID) }
    #expect(!ids.contains("Barbell_Bench_Press"))
}
```

- [ ] **Step 2: Run it — expect FAIL.** ⌘U.

- [ ] **Step 3: Write `PlanService.swift`**

```swift
import Foundation
import FitnessDomain
import ExerciseCatalog
import RuleEngine
import PlanValidation

struct PlanResult {
    let plan: WeeklyPlan
    let issues: [ValidationIssue]
}

struct PlanService {
    let catalog: CatalogStore

    init(catalog: CatalogStore) {
        self.catalog = catalog
    }

    static func live() throws -> PlanService {
        PlanService(catalog: try BundledCatalog.load())
    }

    func generate(for profile: UserProfile, weekStartDate: Date = .now) -> PlanResult {
        let context = profile.makeUserContext()
        let plan = RulePlanBuilder(catalog: catalog).build(context: context, weekStartDate: weekStartDate)
        let issues = PlanValidator(catalog: catalog).validate(plan, context: context)
        return PlanResult(plan: plan, issues: issues)
    }
}
```

- [ ] **Step 4: Add to target, run the tests — expect PASS.** ⌘U.

If `generatesAValidPlanFromTheStubCatalog` fails on `result.issues.isEmpty`: read the issues. A `weeklyVolumeOutOfBand` for a muscle the stub catalog under-serves (e.g. only one exercise so `setsEach` can't reach MEV) is a **stub-catalog gap, not a code bug** — fix by adding a second exercise for that muscle to `catalog.json` (Task 3 file) and re-run. Record which muscle needed it. Do not change `PlanService` or `FitnessCore`.

- [ ] **Step 5: Commit**

```bash
git add FitnessTracker
git commit -m "Add PlanService: profile to validated rule-engine plan"
```

---

## Task 8: Onboarding draft model

**Files:**
- Create: `FitnessTracker/FitnessTracker/Features/Onboarding/OnboardingModel.swift`
- Test: `FitnessTracker/FitnessTrackerTests/OnboardingModelTests.swift`

**Interfaces:**
- Consumes: `FitnessDomain.Goal`, `ExperienceLevel`, `Equipment`, `MuscleGroup`; `UserProfile` (Task 4)
- Produces:
  - `@Observable final class OnboardingModel` with editable fields: `goal: Goal?`, `experience: ExperienceLevel?`, `heightCm: Double`, `weightKg: Double`, `birthYear: Int`, `sex: String`, `sessionsPerWeek: Int` (default 4), `sessionLengthMinutes: Int` (default 60), `equipment: Set<Equipment>`, `excludedMuscles: Set<MuscleGroup>`
  - `var isComplete: Bool` — true when `goal != nil && experience != nil && heightCm > 0 && weightKg > 0 && birthYear >= 1900 && !equipment.isEmpty && (2...7).contains(sessionsPerWeek)`
  - `func makeProfile() -> UserProfile?` — returns `nil` if `!isComplete`, else a `UserProfile` with the raw strings filled from the enum `rawValue`s

- [ ] **Step 1: Write the failing test**

`FitnessTrackerTests/OnboardingModelTests.swift`:
```swift
import Testing
import FitnessDomain
@testable import FitnessTracker

@Test func incompleteUntilRequiredFieldsSet() {
    let m = OnboardingModel()
    #expect(m.isComplete == false)
    #expect(m.makeProfile() == nil)

    m.goal = .buildMuscle
    m.experience = .intermediate
    m.heightCm = 178
    m.weightKg = 76
    m.birthYear = 2001
    m.equipment = [.barbell, .dumbbell]
    #expect(m.isComplete == true)
}

@Test func makeProfileCarriesRawValues() throws {
    let m = OnboardingModel()
    m.goal = .loseFat
    m.experience = .beginner
    m.heightCm = 170; m.weightKg = 82; m.birthYear = 1999
    m.equipment = [.machine, .cable]
    m.excludedMuscles = [.lowerBack]
    let p = try #require(m.makeProfile())
    #expect(p.goalRaw == "loseFat")
    #expect(p.experienceRaw == "beginner")
    #expect(Set(p.availableEquipmentRaws) == ["machine", "cable"])
    #expect(p.excludedMuscleRaws == ["lowerBack"])
}
```

- [ ] **Step 2: Run it — expect FAIL.** ⌘U.

- [ ] **Step 3: Write `OnboardingModel.swift`**

```swift
import Foundation
import FitnessDomain

@Observable
final class OnboardingModel {
    var goal: Goal?
    var experience: ExperienceLevel?
    var heightCm: Double = 0
    var weightKg: Double = 0
    var birthYear: Int = 0
    var sex: String = "unspecified"
    var sessionsPerWeek: Int = 4
    var sessionLengthMinutes: Int = 60
    var equipment: Set<Equipment> = []
    var excludedMuscles: Set<MuscleGroup> = []

    var isComplete: Bool {
        goal != nil && experience != nil
            && heightCm > 0 && weightKg > 0 && birthYear >= 1900
            && !equipment.isEmpty
            && (2...7).contains(sessionsPerWeek)
    }

    func makeProfile() -> UserProfile? {
        guard isComplete, let goal, let experience else { return nil }
        return UserProfile(
            goalRaw: goal.rawValue,
            experienceRaw: experience.rawValue,
            heightCm: heightCm,
            weightKg: weightKg,
            birthYear: birthYear,
            sexRaw: sex,
            sessionsPerWeek: sessionsPerWeek,
            sessionLengthMinutes: sessionLengthMinutes,
            availableEquipmentRaws: equipment.map(\.rawValue),
            excludedMuscleRaws: excludedMuscles.map(\.rawValue),
            excludedExerciseIDs: []
        )
    }
}
```

- [ ] **Step 4: Add to target, run the tests — expect PASS.** ⌘U.

- [ ] **Step 5: Commit**

```bash
git add FitnessTracker
git commit -m "Add OnboardingModel draft state and completion check"
```

---

## Task 9: Onboarding UI

**Files:**
- Create: `FitnessTracker/FitnessTracker/Features/Onboarding/OnboardingView.swift`
- Create: `FitnessTracker/FitnessTracker/Features/Onboarding/Steps/GoalStep.swift`, `ExperienceStep.swift`, `BodyStep.swift`, `ScheduleStep.swift`, `EquipmentStep.swift`, `LimitationsStep.swift`, `ReviewStep.swift`

**Interfaces:**
- Consumes: `OnboardingModel` (Task 8); `FitnessDomain` enums (`CaseIterable`); `PlanService` (Task 7); SwiftData `modelContext`
- Produces: `struct OnboardingView: View` — takes `onComplete: (UserProfile) -> Void`, drives a `NavigationStack` / step index over the 7 steps, and on the Review step's "Create my plan" button calls `onComplete(model.makeProfile()!)` (guarded by `isComplete`).

**This task is SwiftUI-heavy. Verification is: builds, runs in the simulator, and the flow reaches the Review step and fires `onComplete` with a populated profile. A described screenshot per step is the acceptance artifact.**

- [ ] **Step 1: Write `OnboardingView.swift` (step container)**

```swift
import SwiftUI
import FitnessDomain

struct OnboardingView: View {
    let onComplete: (UserProfile) -> Void

    @State private var model = OnboardingModel()
    @State private var stepIndex = 0

    private let stepCount = 7

    var body: some View {
        NavigationStack {
            Group {
                switch stepIndex {
                case 0: GoalStep(model: model)
                case 1: ExperienceStep(model: model)
                case 2: BodyStep(model: model)
                case 3: ScheduleStep(model: model)
                case 4: EquipmentStep(model: model)
                case 5: LimitationsStep(model: model)
                default: ReviewStep(model: model) {
                    if let profile = model.makeProfile() { onComplete(profile) }
                }
            }
            .navigationTitle("Set up (\(stepIndex + 1)/\(stepCount))")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if stepIndex > 0 { Button("Back") { stepIndex -= 1 } }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if stepIndex < stepCount - 1 {
                        Button("Next") { stepIndex += 1 }
                            .disabled(!canAdvance)
                    }
                }
            }
        }
    }

    private var canAdvance: Bool {
        switch stepIndex {
        case 0: model.goal != nil
        case 1: model.experience != nil
        case 2: model.heightCm > 0 && model.weightKg > 0 && model.birthYear >= 1900
        case 3: (2...7).contains(model.sessionsPerWeek)
        case 4: !model.equipment.isEmpty
        default: true
        }
    }
}
```

- [ ] **Step 2: Write the 7 step views**

`GoalStep.swift`:
```swift
import SwiftUI
import FitnessDomain

struct GoalStep: View {
    @Bindable var model: OnboardingModel
    var body: some View {
        List(Goal.allCases, id: \.self) { goal in
            Button {
                model.goal = goal
            } label: {
                HStack {
                    Text(goal.label)
                    Spacer()
                    if model.goal == goal { Image(systemName: "checkmark") }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

extension Goal {
    var label: String {
        switch self {
        case .loseFat: "Lose fat"
        case .buildMuscle: "Build muscle"
        case .getStronger: "Get stronger"
        case .generalFitness: "General fitness"
        }
    }
}
```

`ExperienceStep.swift` — same pattern over `ExperienceLevel.allCases` with a `label` (`beginner` → "New to the gym", `intermediate` → "~6 months – 2 years", `advanced` → "2+ years").

`BodyStep.swift`:
```swift
import SwiftUI

struct BodyStep: View {
    @Bindable var model: OnboardingModel
    var body: some View {
        Form {
            LabeledContent("Height (cm)") {
                TextField("178", value: $model.heightCm, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            LabeledContent("Weight (kg)") {
                TextField("75", value: $model.weightKg, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            Picker("Birth year", selection: $model.birthYear) {
                ForEach(Array(1950...2010).reversed(), id: \.self) { Text(String($0)).tag($0) }
            }
            Picker("Sex", selection: $model.sex) {
                Text("Male").tag("male"); Text("Female").tag("female"); Text("Prefer not to say").tag("unspecified")
            }
        }
    }
}
```

`ScheduleStep.swift`:
```swift
import SwiftUI

struct ScheduleStep: View {
    @Bindable var model: OnboardingModel
    var body: some View {
        Form {
            Stepper("Sessions per week: \(model.sessionsPerWeek)", value: $model.sessionsPerWeek, in: 2...7)
            Picker("Typical session length", selection: $model.sessionLengthMinutes) {
                Text("30 min").tag(30); Text("45 min").tag(45); Text("60 min").tag(60); Text("90 min").tag(90)
            }
            Text("This is a ceiling, not a commitment — the plan adapts to what you actually do.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
```

`EquipmentStep.swift`:
```swift
import SwiftUI
import FitnessDomain

struct EquipmentStep: View {
    @Bindable var model: OnboardingModel
    var body: some View {
        List(Equipment.allCases, id: \.self) { item in
            Button {
                if model.equipment.contains(item) { model.equipment.remove(item) }
                else { model.equipment.insert(item) }
            } label: {
                HStack {
                    Text(item.label)
                    Spacer()
                    if model.equipment.contains(item) { Image(systemName: "checkmark") }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

extension Equipment {
    var label: String {
        switch self {
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbells"
        case .cable: "Cable machine"
        case .machine: "Plate/selectorized machines"
        case .bodyweight: "Bodyweight only"
        case .kettlebell: "Kettlebells"
        case .bands: "Resistance bands"
        case .ezBar: "EZ curl bar"
        case .other: "Other"
        }
    }
}
```

`LimitationsStep.swift` — a `List` of a curated subset of `MuscleGroup` (`.lowerBack`, `.shoulders`, `.knee` is not a muscle — use `.lowerBack`, `.shoulders`, `.biceps`, `.hamstrings` as "areas to avoid loading"); toggling adds/removes from `model.excludedMuscles`. Include a "Skip — no limitations" hint. Keep it short; this is optional.

`ReviewStep.swift`:
```swift
import SwiftUI

struct ReviewStep: View {
    @Bindable var model: OnboardingModel
    let onCreate: () -> Void
    var body: some View {
        Form {
            Section("Summary") {
                LabeledContent("Goal", value: model.goal?.label ?? "—")
                LabeledContent("Experience", value: model.experience.map(String.init(describing:)) ?? "—")
                LabeledContent("Sessions/week", value: "\(model.sessionsPerWeek)")
                LabeledContent("Equipment", value: "\(model.equipment.count) selected")
                if !model.excludedMuscles.isEmpty {
                    LabeledContent("Avoiding", value: "\(model.excludedMuscles.count) areas")
                }
            }
            Section {
                Button("Create my plan", action: onCreate)
                    .disabled(!model.isComplete)
            }
        }
    }
}
```

- [ ] **Step 3: Add all files to the target. Build (⌘B).** Fix any compile errors (missing `import`, `@Bindable` vs `@Bindable var`).

- [ ] **Step 4: Manual verification**

Temporarily set `RootView` to host onboarding:
```swift
struct RootView: View {
    var body: some View {
        OnboardingView { profile in
            print("onboarding complete:", profile.goalRaw, profile.availableEquipmentRaws)
        }
    }
}
```
Run (⌘R). Walk all 7 steps: pick a goal, experience, enter body stats, set schedule, tick ≥1 equipment, optionally an area to avoid, reach Review, tap "Create my plan". Confirm the console prints the profile line.
**Acceptance artifact:** note in the report what each step showed and that "Create my plan" fired.

- [ ] **Step 5: Commit**

```bash
git add FitnessTracker
git commit -m "Add onboarding step flow UI"
```

---

## Task 10: Plan view (read-only)

**Files:**
- Create: `FitnessTracker/FitnessTracker/Features/Plan/PlanView.swift`

**Interfaces:**
- Consumes: `FitnessDomain.WeeklyPlan`, `PlannedSession`, `PlannedItem`; `ExerciseCatalog.CatalogStore` (for exercise display names); `StoredPlan` (Task 6)
- Produces: `struct PlanView: View` — init `PlanView(plan: WeeklyPlan, catalog: CatalogStore)`. Renders the rationale header, a `Section` per session (title = focus muscles), a row per item (exercise name from `catalog.exercise(id:)?.name ?? id`, `"\(targetSets) × \(targetReps.min)–\(targetReps.max)"`, rest, coach note). A footer section lists `weeklyVolumeTargets`.

**SwiftUI-heavy. Verification: builds, runs, shows a plan generated from a real onboarding pass. Described screenshot is the artifact.**

- [ ] **Step 1: Write `PlanView.swift`**

```swift
import SwiftUI
import FitnessDomain
import ExerciseCatalog

struct PlanView: View {
    let plan: WeeklyPlan
    let catalog: CatalogStore

    var body: some View {
        List {
            Section {
                Text(plan.rationale).font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(plan.sessions.sorted { $0.order < $1.order }) { session in
                Section("Session \(session.order + 1) · \(focusText(session))") {
                    ForEach(Array(session.items.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name(for: item.exerciseID)).font(.headline)
                            Text("\(item.targetSets) × \(item.targetReps.min)–\(item.targetReps.max)  ·  rest \(item.restSeconds)s")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text(item.coachNote).font(.footnote).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            Section("Weekly volume targets") {
                ForEach(plan.weeklyVolumeTargets, id: \.muscle) { t in
                    LabeledContent(String(describing: t.muscle), value: "\(t.targetSets) sets")
                }
            }
        }
        .navigationTitle("This week")
    }

    private func name(for id: String) -> String {
        catalog.exercise(id: id)?.name ?? id
    }

    private func focusText(_ session: PlannedSession) -> String {
        session.focusMuscles.map { String(describing: $0) }.joined(separator: ", ")
    }
}
```

- [ ] **Step 2: Add to target. Build (⌘B).**

- [ ] **Step 3: Manual verification**

Temporarily wire `RootView` to run onboarding → generate → show:
```swift
struct RootView: View {
    @State private var result: PlanResult?
    private let service = try? PlanService.live()

    var body: some View {
        NavigationStack {
            if let result, let service {
                PlanView(plan: result.plan, catalog: service.catalog)
            } else {
                OnboardingView { profile in
                    result = service?.generate(for: profile, weekStartDate: .now)
                }
            }
        }
    }
}
```
Run, complete onboarding with full equipment + 4 sessions, confirm a plan appears with sessions, exercises (real names, not ids), sets×reps, and a volume-targets section.
**Acceptance artifact:** describe the rendered plan in the report (session count, a couple of exercise names, that names resolved).

- [ ] **Step 4: Commit**

```bash
git add FitnessTracker
git commit -m "Add read-only plan view"
```

---

## Task 11: Root navigation, persistence wiring, and Settings scaffold

**Files:**
- Modify: `FitnessTracker/FitnessTracker/RootView.swift` (final version)
- Create: `FitnessTracker/FitnessTracker/Features/Settings/SettingsView.swift`

**Interfaces:**
- Consumes: `@Query` for `UserProfile` and `StoredPlan`; `PlanService`; `OnboardingView`; `PlanView`; `SettingsView`; `modelContext`
- Produces: `RootView` that: if no `UserProfile` → `OnboardingView` (on complete: insert profile, generate plan via `PlanService.live()`, insert `StoredPlan`, save); if a `UserProfile` exists → `NavigationStack` with `PlanView` (from the latest `StoredPlan`) + a toolbar link to `SettingsView`. `SettingsView` shows the profile summary, a "Regenerate plan" button, and a "Start over" button (deletes the profile + stored plans → back to onboarding), plus a disabled "AI Coach — Phase 1c" section.

- [ ] **Step 1: Write the final `RootView.swift`**

```swift
import SwiftUI
import SwiftData
import FitnessDomain

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(sort: \StoredPlan.generatedAt, order: .reverse) private var plans: [StoredPlan]

    @State private var catalogStore: (any Sendable)?   // holds CatalogStore; see note
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            if profiles.isEmpty {
                OnboardingView { profile in
                    createPlan(for: profile)
                }
            } else if let latest = plans.first {
                planScreen(latest)
            } else {
                // profile exists but no plan (e.g. generation failed earlier) — offer retry
                ContentUnavailableView {
                    Label("No plan yet", systemImage: "dumbbell")
                } actions: {
                    Button("Generate plan") {
                        if let p = profiles.first { createPlan(for: p, insertProfile: false) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func planScreen(_ stored: StoredPlan) -> some View {
        if let plan = try? stored.decodedPlan(), let service = try? PlanService.live() {
            PlanView(plan: plan, catalog: service.catalog)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                    }
                }
        } else {
            Text("Could not load the saved plan.")
        }
    }

    private func createPlan(for profile: UserProfile, insertProfile: Bool = true) {
        guard let service = try? PlanService.live() else { loadError = "catalog failed to load"; return }
        if insertProfile { context.insert(profile) }
        let result = service.generate(for: profile, weekStartDate: .now)
        if let stored = try? StoredPlan(plan: result.plan, hadValidationIssues: !result.issues.isEmpty) {
            context.insert(stored)
        }
        try? context.save()
    }
}
```

Note on `catalogStore`: `CatalogStore` is `Sendable` but not `Observable`; the simplest correct approach for 1b is to call `PlanService.live()` where needed (it's cheap — parses 20 JSON records). If profiling later shows it matters, cache it in an `@Observable` holder. Do **not** over-engineer this now — the `try? PlanService.live()` calls above are acceptable.

- [ ] **Step 2: Write `SettingsView.swift`**

```swift
import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(sort: \StoredPlan.generatedAt, order: .reverse) private var plans: [StoredPlan]

    var body: some View {
        Form {
            if let p = profiles.first {
                Section("Profile") {
                    LabeledContent("Goal", value: p.goalRaw)
                    LabeledContent("Experience", value: p.experienceRaw)
                    LabeledContent("Sessions/week", value: "\(p.sessionsPerWeek)")
                    LabeledContent("Equipment", value: "\(p.availableEquipmentRaws.count) items")
                }
                Section {
                    Button("Regenerate plan") { regenerate(p) }
                }
                Section {
                    Button("Start over", role: .destructive) { startOver() }
                }
            }
            Section("AI Coach") {
                LabeledContent("Status", value: "Coming in Phase 1c")
            }
            .disabled(true)
        }
        .navigationTitle("Settings")
    }

    private func regenerate(_ profile: UserProfile) {
        guard let service = try? PlanService.live() else { return }
        let result = service.generate(for: profile, weekStartDate: .now)
        if let stored = try? StoredPlan(plan: result.plan, hadValidationIssues: !result.issues.isEmpty) {
            context.insert(stored)
            try? context.save()
        }
    }

    private func startOver() {
        for plan in plans { context.delete(plan) }
        for profile in profiles { context.delete(profile) }
        try? context.save()
    }
}
```

- [ ] **Step 3: Add `SettingsView.swift` to the target. Build (⌘B).**

- [ ] **Step 4: Manual verification (the full loop)**

1. Delete the app from the simulator (clean state). Run (⌘R).
2. Onboarding appears. Complete it (goal, experience, body, 4 sessions, tick Barbell + Dumbbell + Cable + Machine, skip limitations, Review → "Create my plan").
3. Plan view appears with 4 sessions, real exercise names, sets×reps, volume targets.
4. Tap the gear → Settings shows the profile summary. Tap "Regenerate plan" → back out → plan still shows (latest).
5. Settings → "Start over" → app returns to onboarding.
6. Force-quit and relaunch the app → it opens straight to the plan (persistence works).

**Acceptance artifact:** a short numbered report of what each step showed.

- [ ] **Step 5: Commit**

```bash
git add FitnessTracker
git commit -m "Wire root navigation, plan persistence, and Settings scaffold"
```

---

## Task 12: Acceptance pass + docs

**Files:**
- Modify: `docs/HANDOFF.md` (Phase 1b done, next = 1c)
- Modify: `docs/04-roadmap-phases.md` (tick Phase 1b "done when")
- Create: `FitnessTracker/README.md`

**Interfaces:** none — this is the milestone gate.

- [ ] **Step 1: Full test run**

`xcodebuild test -scheme FitnessTracker -destination 'platform=iOS Simulator,name=iPhone 16'` (or ⌘U).
Expected: all `FitnessTrackerTests` pass (BundledCatalog ×2, UserProfilePersistence ×1, UserProfileMapping ×3, StoredPlan ×1, PlanService ×2, OnboardingModel ×2 = ~11), zero warnings. Also `cd FitnessCore && swift test` → still 35/35.

- [ ] **Step 2: Clean-install acceptance on the simulator**

Erase the simulator (Device → Erase All Content and Settings) or delete the app. Run. Perform the full loop from Task 11 Step 4. Confirm all six checks pass.

- [ ] **Step 3: Write `FitnessTracker/README.md`**

```markdown
# FitnessTracker (app)

iOS app shell (Phase 1b). SwiftUI + SwiftData, iOS 26. Depends on the local
`FitnessCore` package for all training logic.

## What it does (1b)
Onboarding → rule-engine weekly plan → read-only plan view. Fully offline, no AI.

## Structure
- `Models/` — `UserProfile`, `StoredPlan` (SwiftData) + `UserProfile → UserContext` mapping
- `Catalog/` — bundled stub `catalog.json` (~20 exercises) + `BundledCatalog` loader
- `Planning/` — `PlanService` (profile → `RulePlanBuilder` → `PlanValidator`)
- `Features/Onboarding|Plan|Settings/` — SwiftUI

## Not yet (Phase 1c)
LLM provider adapters, `AIClient`, `PlanCoordinator` (AI generate → validate →
fallback), real-time cost metering, provider-profile UI.

## Known follow-ups
- Stub catalog → full ~120-exercise curation from `free-exercise-db` (needs the
  user's real equipment list).
- The `FitnessCore/README.md` "Known Phase 1b follow-ups" that need engine/validator
  changes (empty-session handling, zero-volume check, `sessionLengthMinutes`) are
  carried into the Phase 1c plan, not 1b.
```

- [ ] **Step 4: Update `docs/HANDOFF.md`**

In §2, set Phase to "Phase 1b complete — app runs onboarding → rule plan → plan view on the simulator", Next action to "Phase 1c: AI integration (LLM adapters, PlanCoordinator, cost metering)". Add a chronology entry. Bump "Last updated".

- [ ] **Step 5: Commit**

```bash
git add docs FitnessTracker/README.md
git commit -m "Phase 1b acceptance pass and docs"
```

---

## Self-Review

**1. Spec coverage:**

| Spec item | Task |
|-----------|------|
| `docs/04` Phase 1b: onboarding | 8, 9 |
| `docs/04` Phase 1b: bundled catalog + `CatalogStore` | 3 |
| `docs/04` Phase 1b: SwiftData models (profile, plan) | 4, 6 |
| `docs/04` Phase 1b: rule-engine plan generation + validation | 7 |
| `docs/04` Phase 1b: read-only plan view with "why this plan" | 10 |
| `docs/04` Phase 1b: Settings scaffold | 11 |
| `docs/02` §2 onboarding fields (goal, experience, body stats, schedule, equipment, limitations) | 8, 9 |
| `docs/02` §9.4 offline plan viewing | inherent — no network anywhere |
| `docs/03` §10 Xcode app target + local `FitnessCore` package | 2 |
| `docs/03` §3 `UserProfile`-ish + plan persistence | 4, 6 |
| `FitnessCore/README.md` "drop swift-testing dep" | 1 |
| `docs/03` §3 `ProviderProfile` / `AICallRecord` models | **deferred to 1c** (no AI in 1b) |
| `docs/02` §9.1–9.3 provider profiles / cost metering | **deferred to 1c** |

**Gaps / intentional deferrals (documented):**
- **Provider profiles, `AICallRecord`, cost metering, the `$` chip** — all AI-adjacent; Phase 1c per the 1a/1b/1c split.
- **Exercise images** — the stub catalog has empty `images`; the plan view shows text only. Real images arrive with catalog curation.
- **`traps` coverage** — the stub catalog has no `traps`-primary exercise; PPL's pull day silently trains it zero. Acceptable for a stub (documented in Task 3); the volume validator won't flag it (zero-volume blind spot, a known `FitnessCore` follow-up).
- **Equipment / limitations as separate `@Model` types** — 1b stores them as `[String]` arrays on `UserProfile`; richer modelling can come when the InBody/limitations features land.
- **UI tests (XCUITest)** — 1b relies on unit tests for logic + manual simulator acceptance. The SwiftUI views are thin enough that XCUITest overhead isn't justified yet.

**2. Placeholder scan:** No "TBD"/"TODO" as deliverables. Task 4 Step 4 has a `// TODO(Task 6)` that Task 6 Step 4 explicitly removes. Every code step has complete code; SwiftUI-heavy tasks (9, 10, 11) have full view code plus explicit manual acceptance artifacts.

**3. Type consistency:**
- `UserProfile` init label set is identical in Tasks 4, 5, 7, 8. ✅
- `PlanService(catalog:)` / `PlanService.live()` / `PlanResult { plan, issues }` — Tasks 7, 10, 11. ✅
- `BundledCatalog.load(bundle:resourceName:)` — Tasks 3, 7 (tests use `Bundle(for: BundledCatalogTestAnchor.self)`). ✅
- `StoredPlan(plan:hadValidationIssues:)` / `decodedPlan()` — Tasks 6, 10, 11. ✅
- `OnboardingModel` fields / `isComplete` / `makeProfile()` — Tasks 8, 9. ✅
- `makeUserContext()` — Tasks 5, 7. ✅
- `.modelContainer(for: [UserProfile.self, StoredPlan.self])` — Task 4 (partial) → Task 6 (final). ✅

---

## Execution Handoff

Choose after review:

**1. Subagent-Driven (recommended)** — fresh subagent per task; but note Tasks 2, 9, 10, 11 need a human at Xcode for GUI steps and simulator runs, so those tasks are "implementer writes files + instructions → human executes GUI + reports → controller reviews".

**2. Inline Execution** — run tasks in this session via `superpowers:executing-plans`, with you performing the Xcode/simulator steps at the checkpoints.
