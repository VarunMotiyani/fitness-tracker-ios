# Date-Scoped Workout Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable an athlete to add, replace, and remove exercises from a scheduled workout for one date, without changing the recurring routine, while keeping Home, Start, export, and AI context consistent.

**Architecture:** A `DayWorkoutOverride` is a JSON-persisted, date-keyed full item snapshot kept beside the existing day schedule overrides in `WorkoutScheduleStore`. `effectiveSession(for:in:)` becomes the single read path for a scheduled date. The Home day sheet presents the effective exercise list and delegates add/replace selection to the existing Exercises tab through a transient RootView navigation intent.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, FitnessDomain, ExerciseCatalog, RuleEngine, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-09-day-workout-overrides-design.md`

## Global Constraints

- An edit applies only to its ISO calendar date and never mutates `WeeklyPlan.sessions` or recurring weekdays.
- Candidate exercises must intersect the base session’s focus muscles and cannot duplicate an effective item.
- Additions use exactly 3 sets, 8–12 reps, no prescribed load, and 90 seconds rest.
- Manual edits use `.manual`; the data contract must retain `.ai` for future AI callers.
- Do not create, boot, reset, terminate, close, or open another simulator window. Reuse the existing shared simulator only for the final visual check.
- Run focused tests for each task; do not run the entire suite for an isolated change.
- Preserve unrelated dirty-worktree changes and never commit them.

---

## Parallel Work Map

Each unit has exclusive file ownership. Run each in a separate worktree/branch, merge **U1/U2 in parallel → U3/U4 in parallel → U5**. A worker must not change files assigned to another unit; UI integration happens only in U4.

| Unit | Suggested owner | Deliverable | Exclusive files | Depends on |
|---|---|---|---|---|
| U1 | Claude | Durable date-scoped override store + focused tests | `Scheduling/WorkoutScheduleStore.swift`, `WorkoutScheduleStoreTests.swift` | — |
| U2 | Codex | Pure Exercises-tab intent + filtering/copy tests | new `Features/Library/ExerciseLibraryIntent.swift`, new `ExerciseLibraryIntentTests.swift` | — |
| U3 | Claude | Effective-session use outside Home plus export/AI visibility | `Features/Session/WorkoutTabView.swift`, `AI/ProactiveCoordinator.swift`, `AI/Tools/SuggestionTools.swift`, `Export/HistoryExportManager.swift`, `HistoryExportManagerTests.swift` | U1 |
| U4 | Codex | Day sheet, Root/Home navigation, contextual Exercises tab and detail-page integration | `Features/Home/DayOverrideSheet.swift`, `WorkoutDayPresentationTests.swift`, `RootView.swift`, `Features/Home/HomeView.swift`, `Features/Library/LibraryView.swift`, `Features/Library/ExerciseDetailSheet.swift` | U1, U2 |
| U5 | Codex | Cross-flow regression check, existing-simulator visual review, conflict resolution | only files with an observed integration defect | U1–U4 |

### U1 — Persistent effective-workout store (Claude)

**Contract to implement exactly:** `DayWorkoutOverride`, `dayWorkoutOverrideKey`, `dayWorkoutOverrides`, `saveDayWorkoutOverride`, `removeDayWorkoutOverride(for:)`, `effectiveSession(for:in:)`, `replaceExercise`, `addExercise`, and `removeExercise`, as defined in Task 1 below.

**Acceptance:** one date’s items change without changing `WeeklyPlan.sessions`; non-focus and duplicate exercises are rejected; stale base-session overrides are ignored. Run only `WorkoutScheduleStoreTests`.

### U2 — Library intent contract (Codex)

**Contract to implement exactly:** `ExerciseLibraryIntent` with `Action.add`, `Action.replace(existingExerciseID:)`, `accepts(_:)`, and `actionTitle(existingName:)`, as defined in Task 3 below.

**Acceptance:** Push accepts chest/triceps/shoulder candidates and rejects back/pull-only candidates. Run only `ExerciseLibraryIntentTests`. This unit must not wire navigation or mutate a workout.

### U3 — Consumer and AI/export alignment (Claude)

**Contract to consume:** U1’s `effectiveSession(for:in:)` and `dayWorkoutOverrides`.

**Acceptance:** Start tab and AI scheduled-day reasoning use effective items; JSON export includes stable, date-sorted `workoutOverrides` with origin and item prescription data. Run only `HistoryExportManagerTests` plus a build after U1 is merged. This unit must not modify `RootView`, `HomeView`, or the day sheet.

### U4 — Day editor, navigation, Library, and detail-page integration (Codex)

**Contract to consume:** U1 store helpers and U2 pure intent.

**Implementation boundary:** DayOverrideSheet owns the thumbnail-led editor, connected Change disclosure, and confirmation-protected Rest footer. Root owns the intent and `reopenDayOverrideDate`; Home forwards the closure and reopens the sheet after a successful selection; Library adds scoped selection mode; ExerciseDetailSheet adds date-scoped Add/Replace/Remove controls. This is the only unit that changes day sheet, Root, Home, Library, or detail files.

**Acceptance:** an athlete opens an image-rich detail page before committing; selection changes today only, routes back to the day sheet, and normal Exercises browsing remains unchanged. Run only `ExerciseLibraryIntentTests` plus a build after U1–U3 are merged.

### U5 — Integration and visual verification (Codex)

**Acceptance:** run the focused combined suite in Task 6; resolve only observed integration defects; build/install/launch only in the existing shared iPhone 17 Pro simulator; capture the planned-card editor, contextual Library header, and detail-page action states; leave the existing simulator window open.

---

### Task 1: Persist and resolve date-scoped workout overrides

**Files:**
- Modify: `FitnessTracker/FitnessTracker/Scheduling/WorkoutScheduleStore.swift`
- Modify: `FitnessTracker/FitnessTrackerTests/WorkoutScheduleStoreTests.swift`

**Interfaces:**
- Produces `DayWorkoutOverride`, `DayWorkoutOverride.Origin`, `WorkoutScheduleStore.dayWorkoutOverrideKey`, `dayWorkoutOverrides`, `effectiveSession(for:in:)`, `replaceExercise`, `addExercise`, `removeExercise`, and `removeDayWorkoutOverride`.
- Consumes `WeeklyPlan`, `PlannedSession`, `PlannedItem`, `Exercise`, `CatalogStore`, and `Scheduling.isoDateKey`.
- Later tasks must call `effectiveSession(for:in:)` for any date-specific workout and must mutate only through the helper methods below.

- [ ] **Step 1: Write the failing effective-session and mutation tests**

Add a clean-store key for `dayWorkoutOverrideKey`, then add a Push-session fixture and these tests:

```swift
private func pushPlan() -> WeeklyPlan {
    WeeklyPlan(weekStartDate: date(2026, 9, 7), source: .ruleEngine, rationale: "test",
               sessions: [PlannedSession(id: UUID(), order: 0, focusMuscles: [.chest, .shoulders, .triceps],
                   items: [
                       PlannedItem(exerciseID: "bench", targetSets: 3, targetReps: RepRange(min: 6, max: 8), targetLoadKg: 60, restSeconds: 120, coachNote: ""),
                       PlannedItem(exerciseID: "triceps_pressdown", targetSets: 3, targetReps: RepRange(min: 10, max: 12), targetLoadKg: nil, restSeconds: 90, coachNote: "")
                   ])], weeklyVolumeTargets: [])
}

private func schedule(_ plan: WeeklyPlan, on date: Date) {
    WorkoutScheduleStore.saveDayPlan([
        Scheduling.isoDateKey(date, calendar: WorkoutScheduleStore.calendar): plan.sessions[0].id.uuidString
    ])
}

private func exercise(_ id: String, primary: MuscleGroup) -> Exercise {
    Exercise(id: id, name: id, primaryMuscle: primary, secondaryMuscles: [],
             equipment: .machine, mechanic: .compound, force: .push,
             difficulty: .intermediate, isUnilateral: false, instructions: [], imagePaths: [])
}

private func pushCatalog(including extraIDs: [String] = []) -> CatalogStore {
    var exercises = [
        exercise("bench", primary: .chest),
        exercise("machine_press", primary: .chest),
        exercise("triceps_pressdown", primary: .triceps)
    ]
    if extraIDs.contains("row") { exercises.append(exercise("row", primary: .back)) }
    return CatalogStore(exercises: exercises)
}

@Test func dateOverrideReplacesAnExerciseWithoutMutatingWeeklyPlan() {
    withCleanStore {
        let date = date(2026, 9, 9)
        let plan = pushPlan()
        let catalog = pushCatalog()
        schedule(plan, on: date)

        #expect(WorkoutScheduleStore.replaceExercise(
            "bench", with: catalog.exercise(id: "machine_press")!,
            on: date, in: plan, catalog: catalog, origin: .manual))

        let effective = WorkoutScheduleStore.effectiveSession(for: date, in: plan)!
        #expect(effective.items.map(\.exerciseID) == ["machine_press", "triceps_pressdown"])
        #expect(plan.sessions[0].items.map(\.exerciseID) == ["bench", "triceps_pressdown"])
    }
}

@Test func incompatibleOrDuplicateExerciseIsRejected() {
    withCleanStore {
        let date = date(2026, 9, 9)
        let plan = pushPlan()
        let catalog = pushCatalog(including: ["row"])
        schedule(plan, on: date)

        #expect(!WorkoutScheduleStore.addExercise(catalog.exercise(id: "row")!, on: date, in: plan, catalog: catalog, origin: .manual))
        #expect(!WorkoutScheduleStore.addExercise(catalog.exercise(id: "bench")!, on: date, in: plan, catalog: catalog, origin: .manual))
    }
}

@Test func staleBaseSessionOverrideIsIgnored() {
    withCleanStore {
        let date = date(2026, 9, 9)
        let plan = pushPlan()
        schedule(plan, on: date)
        WorkoutScheduleStore.saveDayWorkoutOverride(.init(
            dateKey: Scheduling.isoDateKey(date, calendar: WorkoutScheduleStore.calendar),
            baseSessionID: UUID(), focusMuscles: [.chest], items: [], origin: .manual, updatedAt: date))

        #expect(WorkoutScheduleStore.effectiveSession(for: date, in: plan)?.items.map(\.exerciseID) == ["bench", "triceps_pressdown"])
    }
}
```

- [ ] **Step 2: Run the focused tests to confirm they fail**

Run:

```bash
xcodebuild test -project FitnessTracker/FitnessTracker.xcodeproj -scheme FitnessTracker -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' -only-testing:FitnessTrackerTests/WorkoutScheduleStoreTests -parallel-testing-enabled NO -quiet
```

Expected: compilation failure because `DayWorkoutOverride`, `effectiveSession`, and its mutation helpers do not exist.

- [ ] **Step 3: Add the persisted override contract and read API**

In `WorkoutScheduleStore.swift`, define the file-scoped Codable contract and JSON store key:

```swift
struct DayWorkoutOverride: Codable, Equatable {
    enum Origin: String, Codable { case manual, ai }
    let dateKey: String
    let baseSessionID: UUID
    let focusMuscles: [MuscleGroup]
    let items: [PlannedItem]
    let origin: Origin
    let updatedAt: Date
}

static let dayWorkoutOverrideKey = "gym_day_workout_overrides_json"
static var dayWorkoutOverrides: [String: DayWorkoutOverride] {
    decode([String: DayWorkoutOverride].self, key: dayWorkoutOverrideKey) ?? [:]
}
```

Implement `effectiveSession(for:in:)` by resolving `plannedSession(for:in:)`, then accepting an override only when its `baseSessionID` equals the resolved session ID and its items are nonempty. Return a new `PlannedSession` with unchanged ID, order, and focus muscles but the stored items. Otherwise return the scheduled session unchanged.

- [ ] **Step 4: Add safe full-snapshot mutation helpers**

Implement helpers that start from `effectiveSession` and save a full snapshot:

```swift
@discardableResult
static func replaceExercise(
    _ existingID: String, with replacement: Exercise, on date: Date,
    in plan: WeeklyPlan, catalog: CatalogStore, origin: DayWorkoutOverride.Origin
) -> Bool

@discardableResult
static func addExercise(
    _ exercise: Exercise, on date: Date, in plan: WeeklyPlan,
    catalog: CatalogStore, origin: DayWorkoutOverride.Origin
) -> Bool

@discardableResult
static func removeExercise(
    _ exerciseID: String, on date: Date, in plan: WeeklyPlan
) -> Bool
```

Use `Set(base.focusMuscles)` and `[exercise.primaryMuscle] + exercise.secondaryMuscles` to validate compatibility. Refuse duplicate IDs and refuse removal when it would leave no items. Replacement preserves `targetSets`, `targetReps`, `targetLoadKg`, `restSeconds`, and `coachNote`; addition creates:

```swift
PlannedItem(exerciseID: exercise.id, targetSets: 3,
            targetReps: RepRange(min: 8, max: 12), targetLoadKg: nil,
            restSeconds: 90, coachNote: "")
```

`saveDayWorkoutOverride` must replace the same date key, encode the complete dictionary, and set `updatedAt: .now`. `removeDayWorkoutOverride(for:)` removes that key and persists the remaining dictionary.

- [ ] **Step 5: Run the focused store tests and inspect the diff**

Run the Step 2 command again. Expected: all `WorkoutScheduleStoreTests` pass. Then run:

```bash
git diff --check -- FitnessTracker/FitnessTracker/Scheduling/WorkoutScheduleStore.swift FitnessTracker/FitnessTrackerTests/WorkoutScheduleStoreTests.swift
```

Expected: no whitespace errors.

### Task 2: Move date-based consumers and export onto the effective session

**Files:**
- Modify: `FitnessTracker/FitnessTracker/Features/Session/WorkoutTabView.swift`
- Modify: `FitnessTracker/FitnessTracker/AI/ProactiveCoordinator.swift`
- Modify: `FitnessTracker/FitnessTracker/AI/Tools/SuggestionTools.swift`
- Modify: `FitnessTracker/FitnessTracker/Export/HistoryExportManager.swift`
- Modify: `FitnessTracker/FitnessTrackerTests/HistoryExportManagerTests.swift`

**Interfaces:**
- Consumes `WorkoutScheduleStore.effectiveSession(for:in:)` from Task 1.
- Produces a date-level export payload with `workoutOverrides` and `currentWeek[].plannedItems`.
- Does not alter direct `plan.sessions` reads that intentionally describe the recurring routine.

- [ ] **Step 1: Write a failing export test for manual workout overrides**

Create a dated Push `WeeklyPlan`, store it in the in-memory `StoredPlan`, save a manual override through Task 1’s API, then assert:

```swift
let data = HistoryExportManager.exportFullJSONData(context: ctx, catalog: catalog())!
let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
let schedule = json["schedule"] as! [String: Any]
let overrides = schedule["workoutOverrides"] as! [[String: Any]]

#expect(overrides.count == 1)
#expect(overrides[0]["origin"] as? String == "manual")
#expect((overrides[0]["items"] as? [[String: Any]])?.first?["exerciseID"] as? String == "machine_press")
```

- [ ] **Step 2: Run only the export test to confirm it fails**

Run:

```bash
xcodebuild test -project FitnessTracker/FitnessTracker.xcodeproj -scheme FitnessTracker -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' -only-testing:FitnessTrackerTests/HistoryExportManagerTests -parallel-testing-enabled NO -quiet
```

Expected: `workoutOverrides` is absent from the exported JSON.

- [ ] **Step 3: Replace date-specific scheduled reads**

For the non-Home date-based consumers owned by this unit, replace only this shape:

```swift
WorkoutScheduleStore.plannedSession(for: date, in: plan)
```

with:

```swift
WorkoutScheduleStore.effectiveSession(for: date, in: plan)
```

Apply it in WorkoutTabView’s today session, proactive missing-session selection, and the AI suggestion schedule payload. Preserve fallback `plan.sessions` behavior for starting a deliberately unscheduled routine. U3 and U5 handle the day sheet, Home, and Root start action without overlapping these files.

- [ ] **Step 4: Export the override and resolved planned items**

In `HistoryExportManager.exportFullJSONData`, serialize each `DayWorkoutOverride` in a stable date-sorted list:

```swift
[
  "date": override.dateKey,
  "baseSessionID": override.baseSessionID.uuidString,
  "origin": override.origin.rawValue,
  "updatedAt": df.string(from: override.updatedAt),
  "items": override.items.map(itemPayload)
]
```

Add a small local `itemPayload(_:)` builder that includes `exerciseID`, `targetSets`, `repMin`, `repMax`, `targetLoadKg`, `restSeconds`, and `coachNote`. For `schedule.currentWeek`, resolve with `effectiveSession` and include the same `plannedItems` field when a session exists.

- [ ] **Step 5: Run the focused export tests and compile the app**

Run the Step 2 test command again, then:

```bash
xcodebuild build -project FitnessTracker/FitnessTracker.xcodeproj -scheme FitnessTracker -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' -quiet
```

Expected: export tests pass and the app compiles with every date consumer using the same effective workout.

### Task 3: Add the contextual Exercises-tab selection handoff

**Files:**
- Create: `FitnessTracker/FitnessTracker/Features/Library/ExerciseLibraryIntent.swift`
- Create: `FitnessTracker/FitnessTrackerTests/ExerciseLibraryIntentTests.swift`

**Interfaces:**
- Produces `ExerciseLibraryIntent` and `ExerciseLibraryIntent.Action`:

```swift
struct ExerciseLibraryIntent: Equatable {
    enum Action: Equatable { case add; case replace(existingExerciseID: String) }
    let date: Date
    let session: PlannedSession
    let action: Action
}
```

- Task 5 owns RootView, HomeView, LibraryView, and ExerciseDetailSheet integration. This unit intentionally creates only a pure, Equatable navigation payload.

- [ ] **Step 1: Write failing compatibility and display-mode tests**

Add pure tests against the intent helpers:

```swift
private let pushSession = PlannedSession(
    id: UUID(), order: 0, focusMuscles: [.chest, .triceps, .shoulders],
    items: [PlannedItem(exerciseID: "bench", targetSets: 3,
                        targetReps: RepRange(min: 6, max: 8), targetLoadKg: 60,
                        restSeconds: 120, coachNote: "")])
private let chestExercise = Exercise(id: "machine_press", name: "Machine Press",
    primaryMuscle: .chest, secondaryMuscles: [.triceps], equipment: .machine,
    mechanic: .compound, force: .push, difficulty: .intermediate,
    isUnilateral: false, instructions: [], imagePaths: [])
private let tricepsAccessory = Exercise(id: "pressdown", name: "Pressdown",
    primaryMuscle: .triceps, secondaryMuscles: [], equipment: .cable,
    mechanic: .isolation, force: .push, difficulty: .intermediate,
    isUnilateral: false, instructions: [], imagePaths: [])
private let backExercise = Exercise(id: "row", name: "Row", primaryMuscle: .back,
    secondaryMuscles: [.biceps], equipment: .cable, mechanic: .compound,
    force: .pull, difficulty: .intermediate, isUnilateral: false,
    instructions: [], imagePaths: [])

@Test func candidateMustMatchTheSessionFocus() {
    let intent = ExerciseLibraryIntent(date: .now, session: pushSession, action: .add)
    #expect(intent.accepts(chestExercise))
    #expect(intent.accepts(tricepsAccessory))
    #expect(!intent.accepts(backExercise))
}

@Test func replacementCopyNamesTheCurrentExercise() {
    let intent = ExerciseLibraryIntent(date: .now, session: pushSession, action: .replace(existingExerciseID: "bench"))
    #expect(intent.actionTitle(existingName: "Bench Press") == "Replace Bench Press")
}
```

- [ ] **Step 2: Run the focused intent tests to confirm they fail**

Run:

```bash
xcodebuild test -project FitnessTracker/FitnessTracker.xcodeproj -scheme FitnessTracker -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' -only-testing:FitnessTrackerTests/ExerciseLibraryIntentTests -parallel-testing-enabled NO -quiet
```

Expected: compilation failure because `ExerciseLibraryIntent` does not exist.

- [ ] **Step 3: Define the pure intent**

Make `ExerciseLibraryIntent.accepts(_:)` intersect `Set(session.focusMuscles)` with the candidate’s primary and secondary muscles. `actionTitle(existingName:)` must return exactly `Add to today’s workout` for `.add` and `Replace <existingName>` for `.replace`. Do not add a closure, a store dependency, or any UI mutation to this value type.

- [ ] **Step 4: Run the focused intent tests**

Run the Step 2 test command again. Expected: compatibility tests pass and the intent remains a pure type with no UI or persistence dependency.

### Task 4: Redesign the day sheet around the effective exercise list

**Files:**
- Modify: `FitnessTracker/FitnessTracker/Features/Home/DayOverrideSheet.swift`
- Modify: `FitnessTracker/FitnessTracker/Features/Home/HomeView.swift`
- Modify: `FitnessTracker/FitnessTrackerTests/WorkoutDayPresentationTests.swift`

**Interfaces:**
- Consumes `effectiveSession`, Task 1 mutation APIs, and Task 3’s `ExerciseLibraryIntent` handoff.
- Produces an expanded planned-card editor, attached Change Workout disclosure, reset action, and confirmation-protected rest control.

- [ ] **Step 1: Add failing day-presentation tests**

Keep these tests pure, covering copy and ordering rather than SwiftUI internals:

```swift
enum DayEditorAction: Equatable {
    case plannedWorkout, changeWorkout, changeChoices, resetWorkout, checkIn, restToday
}

enum DayEditorActionOrder {
    static func visibleActions(showChangeOptions: Bool) -> [DayEditorAction] {
        showChangeOptions
            ? [.plannedWorkout, .changeWorkout, .changeChoices, .resetWorkout, .checkIn, .restToday]
            : [.plannedWorkout, .changeWorkout, .checkIn, .restToday]
    }
}

@Test func customDayUsesCustomForTodayLabel() {
    #expect(WorkoutDayPresentation.planLabel(isCustomized: true) == "Custom for today")
}

@Test func exerciseEditorActionOrderKeepsRestOutOfChangeGroup() {
    #expect(DayEditorActionOrder.visibleActions(showChangeOptions: true) == [.plannedWorkout, .changeWorkout, .changeChoices, .resetWorkout, .checkIn, .restToday])
}
```

- [ ] **Step 2: Run the focused day-presentation tests to confirm they fail**

Run:

```bash
xcodebuild test -project FitnessTracker/FitnessTracker.xcodeproj -scheme FitnessTracker -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' -only-testing:FitnessTrackerTests/WorkoutDayPresentationTests -parallel-testing-enabled NO -quiet
```

Expected: missing presentation helpers and the new custom label.

- [ ] **Step 3: Replace the planned-card behavior with a visible exercise editor**

Make the planned workout card a button that toggles `showExerciseEditor`. When expanded, render its `effectiveSession.items` using `ExerciseThumbnailView`, exercise name, and `sets × reps` prescription. Each row opens the existing `ExerciseDetailSheet` for instruction/media review. Add `onEditExerciseList: (ExerciseLibraryIntent) -> Void = { _ in }`; Task 5 will supply its contextual action configuration and navigation callback. Add a full-width `Add exercise` row that emits:

```swift
ExerciseLibraryIntent(date: date, session: session, action: .add)
```

Show `Custom for today` instead of `Planned workout` whenever `WorkoutScheduleStore.dayWorkoutOverride(for: date, in: plan) != nil`, plus an inline **Reset today’s workout** action calling `removeDayWorkoutOverride(for:)`.

- [ ] **Step 4: Recompose the change and rest actions**

Place the green Change Workout trigger and its expanded compatible choices inside one `VStack(spacing: 0)` with a shared rounded background. Filter routine alternatives to sessions whose focus-muscle sets intersect the effective session’s focus muscles. Keep the existing routine date override write callback for choosing one of those sessions.

Move Rest today to the bottom, after the check-in section, as:

```swift
Button("Need recovery? Rest today", role: .destructive) { showRestConfirmation = true }
    .font(.system(size: 14, weight: .semibold))
```

Confirm with `confirmationDialog("Rest today?", isPresented: $showRestConfirmation)`, explain that it skips only this date, and use the existing `onSaveOverride?("rest")` only after confirmation.

- [ ] **Step 5: Run focused day tests and compile**

Run the Step 2 test command again, then Task 2’s build command. Expected: the change group order is stable, rest is outside the disclosure, and the day sheet reflects the persisted effective items.

### Task 5: Wire Root/Home to contextual Library and exercise detail actions

**Files:**
- Modify: `FitnessTracker/FitnessTracker/RootView.swift`
- Modify: `FitnessTracker/FitnessTracker/Features/Home/HomeView.swift`
- Modify: `FitnessTracker/FitnessTracker/Features/Home/DayOverrideSheet.swift`
- Modify: `FitnessTracker/FitnessTracker/Features/Library/LibraryView.swift`
- Modify: `FitnessTracker/FitnessTracker/Features/Library/ExerciseDetailSheet.swift`

**Interfaces:**
- Consumes U1 `addExercise`, `replaceExercise`, and `removeExercise`; U2 `ExerciseLibraryIntent`; Task 4 `onEditExerciseList`.
- Produces the real tab handoff, safe return to the day sheet, and date-scoped detail actions.

- [ ] **Step 1: Wire Root-owned selection and return state**

Add these two state properties to RootView:

```swift
@State private var exerciseLibraryIntent: ExerciseLibraryIntent?
@State private var reopenDayOverrideDate: Date?
```

Pass `$reopenDayOverrideDate` and an `onEditExerciseList` closure through HomeView. The closure stores `intent.date` in `reopenDayOverrideDate`, sets `exerciseLibraryIntent = intent`, then selects `.exercises`. Pass the intent binding and an `onWorkoutSelectionCommitted(date:)` closure to LibraryView; that closure sets `.home` and restores `reopenDayOverrideDate`.

- [ ] **Step 2: Add LibraryView’s scoped selection mode**

When the intent binding is nil, preserve the current browse experience exactly. When it is non-nil, show `Editing today’s <workout title>` and `Choose a push-compatible exercise`, include `intent.accepts(exercise)` in `filteredExercises`, and hide custom-exercise and generic Plan controls. An exercise tap still opens its detail view; it never saves immediately.

- [ ] **Step 3: Add contextual detail actions and persist only after confirmation**

Extend ExerciseDetailSheet with optional context, then update DayOverrideSheet’s expanded exercise rows to pass the current day’s replace/remove callbacks:

```swift
var selectionTitle: String? = nil
var onSelectForToday: (() -> Bool)? = nil
var onReplaceForToday: (() -> Void)? = nil
var onRemoveFromToday: (() -> Bool)? = nil
```

When context is present, render the primary green selection action beneath instructions. For an existing day-list item, render **Replace exercise** (calling `onReplaceForToday`, which opens the scoped Exercises tab) plus a confirmation-protected **Remove from today**. `LibraryView` calls U1’s add/replace helper only when `onSelectForToday` is pressed. If it returns false, keep the detail sheet open and show `That exercise is already in today’s workout.`; on success, dismiss detail, clear the intent, and invoke Root’s completion callback.

- [ ] **Step 4: Reopen the day sheet after success**

HomeView observes `reopenDayOverrideDate`; when non-nil it sets `activeSheet = .dayOverride(date)` and clears the binding. Verify cancellation leaves the athlete browsing Exercises and never opens the day sheet unexpectedly.

- [ ] **Step 5: Run focused intent and day-presentation tests, then build**

Run the Task 3 and Task 4 focused test commands, then Task 2’s build command. Expected: normal Library browsing remains unchanged; compatible selection returns to the refreshed day editor; incompatible and duplicate selections make no mutation.

### Task 6: Final targeted integration and visual verification

**Files:**
- Modify only if a focused integration failure identifies a real gap in a Task 1–5 file.

**Interfaces:**
- Verifies the completed `DayWorkoutOverride` flow across schedule store, Library intent, Home, Start, export, and AI consumers.

- [ ] **Step 1: Run only the related test groups together**

Run:

```bash
xcodebuild test -project FitnessTracker/FitnessTracker.xcodeproj -scheme FitnessTracker -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' -only-testing:FitnessTrackerTests/WorkoutScheduleStoreTests -only-testing:FitnessTrackerTests/ExerciseLibraryIntentTests -only-testing:FitnessTrackerTests/WorkoutDayPresentationTests -only-testing:FitnessTrackerTests/HistoryExportManagerTests -parallel-testing-enabled NO -quiet
```

Expected: all date-override, export, and UI-presentation logic passes. Do not run unrelated test suites.

- [ ] **Step 2: Build and install on the existing simulator only**

Run the Task 2 build command. Locate the existing Debug simulator app product, then install and launch it only with the shared device ID `B29C47DD-D3FE-490C-9A84-3D9A32AFE68A`. Do not create, boot, reset, terminate, close, or open a simulator window.

- [ ] **Step 3: Manually verify the approved flows in the existing window**

Verify all of the following and capture a screenshot without closing the window:

1. Planned workout tap expands a thumbnail-led Push exercise list.
2. Tapping an exercise opens its instructions/media detail before any mutation is committed.
3. Replace and Add enter the actual Exercises tab with the Push-only context header; a selected compatible exercise returns to the day sheet and updates today only.
4. A Pull/Back exercise is absent from the contextual list.
5. Change Workout’s revealed choices remain visually joined to its trigger; Rest today is small, bottom-aligned, and confirmation-protected.
6. Start and Home show the same changed exercise list, while the next recurring Push session remains unchanged.
7. The history export includes the manual override and its edited planned items.

- [ ] **Step 4: Final diff hygiene**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace failures. Report only files created or changed for this feature; do not alter or stage unrelated worktree changes.
