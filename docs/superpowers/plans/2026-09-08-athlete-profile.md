# Athlete Profile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a dedicated Profile destination where an athlete can update the
identity, training and body-composition information that drives future plans.

**Architecture:** `UserProfile` remains the one current-profile SwiftData row.
`AthleteProfileDraft` is a value-type edit buffer with validation and
plan-input comparison, while `AthleteProfileStore` applies an approved draft in
one SwiftData transaction and keeps the weight timeline in sync. SwiftUI views
render the summary and editor from that draft; they call the existing
`generateAndStore` path only when the athlete explicitly asks to regenerate.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing, FitnessDomain,
ExerciseCatalog.

**Spec:** `docs/superpowers/specs/2026-09-08-athlete-profile-design.md`

## Global Constraints

- iOS 26+, SwiftUI and SwiftData only; add no package dependency.
- Keep `UserProfile` the sole current-profile record; future InBody confirmation
  writes the same optional body-composition fields.
- No camera, photo-library, image storage, scan model, vision API, or scan
  history in this plan.
- Stable identity fields (height, birth year, sex) remain manual-only.
- A changed manual weight updates or inserts a same-day `BodyweightEntryModel`.
- Current plan remains untouched until the athlete taps `Regenerate weekly plan`.
- The Plan tab remains the manual routine/schedule editor.
- Use system Dynamic Type, SF Symbols, GymTheme semantic colours, labels for
  every input, 44pt tap targets, and dark-mode-safe contrast.
- Run only focused test classes plus the app build; do not run the full suite.
- Do not alter unrelated AI/provider, coach-note, or audit-document changes.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `FitnessTracker/FitnessTracker/Models/UserProfile.swift` | Persist optional current body-composition fields with backward-compatible defaults. |
| `FitnessTracker/FitnessTracker/Profile/AthleteProfileDraft.swift` | Snapshot, validate and compare editable profile values. |
| `FitnessTracker/FitnessTracker/Profile/AthleteProfileStore.swift` | Atomically apply a valid draft and upsert a same-day bodyweight entry. |
| `FitnessTracker/FitnessTracker/Features/Profile/AthleteProfileView.swift` | Dedicated summary, plan actions and full edit form. |
| `FitnessTracker/FitnessTracker/Features/Home/HomeView.swift` | Profile entry and relocated daily check-in action. |
| `FitnessTracker/FitnessTracker/Features/Settings/SettingsView.swift` | Route Athlete Profile section to the shared Profile view. |
| `FitnessTracker/FitnessTracker/RootView.swift` | Provide the Plan-tab navigation callback from Home. |
| `FitnessTracker/FitnessTrackerTests/UserProfilePersistenceTests.swift` | SwiftData round-trip coverage for new optional fields. |
| `FitnessTracker/FitnessTrackerTests/AthleteProfileDraftTests.swift` | Validation, plan-input change detection and persistence/timeline tests. |

### Task 1: Profile state and persistence seam

**Files:**
- Modify: `FitnessTracker/FitnessTracker/Models/UserProfile.swift`
- Create: `FitnessTracker/FitnessTracker/Profile/AthleteProfileDraft.swift`
- Create: `FitnessTracker/FitnessTracker/Profile/AthleteProfileStore.swift`
- Modify: `FitnessTracker/FitnessTrackerTests/UserProfilePersistenceTests.swift`
- Create: `FitnessTracker/FitnessTrackerTests/AthleteProfileDraftTests.swift`

**Interfaces:**

```swift
struct AthleteProfileDraft: Equatable {
    init(profile: UserProfile)
    var validationError: String? { get }
    func changesPlanInput(comparedTo profile: UserProfile) -> Bool
}

@MainActor
enum AthleteProfileStore {
    static func apply(_ draft: AthleteProfileDraft,
                      to profile: UserProfile,
                      in context: ModelContext,
                      now: Date = .now) throws
}
```

- [ ] **Step 1: Write failing persistence tests.**

Add a `roundTripsBodyCompositionFieldsThroughSwiftData` test that persists
`bodyFatPercent: 18.2`, `skeletalMuscleMassKg: 34.8`, `totalBodyWaterL: 45.1`,
`basalMetabolicRateKcal: 1820`, and `phaseAngleDegrees: 6.1`, fetches the row,
and expects those exact optional values. Add draft/store tests that:

```swift
@Test func profileChangesUpdatePlanningContextAndWeightTimeline() throws {
    let profile = makeProfile(weightKg: 75)
    let draft = AthleteProfileDraft(profile: profile)
        .with(goalRaw: "loseFat", sessionsPerWeek: 5, weightKg: 74.6)
    #expect(draft.changesPlanInput(comparedTo: profile))
    try AthleteProfileStore.apply(draft, to: profile, in: context,
                                  now: Date(timeIntervalSince1970: 1_700_000_000))
    #expect(profile.makeUserContext().goal == .loseFat)
    #expect(profile.makeUserContext().sessionsPerWeek == 5)
    #expect(try context.fetch(FetchDescriptor<BodyweightEntryModel>()).map(\.kg) == [74.6])
}
```

Also cover invalid height, invalid 101% body fat, negative SMM, and saving a
non-weight profile edit without creating a weight row.

- [ ] **Step 2: Run the new focused tests and confirm they fail because the
  draft/store types and fields do not yet exist.**

Run:

```bash
xcodebuild test -quiet -project FitnessTracker/FitnessTracker.xcodeproj \
  -scheme FitnessTracker \
  -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' \
  -only-testing:FitnessTrackerTests/UserProfilePersistenceTests \
  -only-testing:FitnessTrackerTests/AthleteProfileDraftTests
```

- [ ] **Step 3: Add optional current-composition fields and draft validation.**

Add `Double?` properties with `nil` defaults in `UserProfile`:

```swift
var bodyFatPercent: Double?
var skeletalMuscleMassKg: Double?
var bodyFatMassKg: Double?
var fatFreeMassKg: Double?
var totalBodyWaterL: Double?
var proteinKg: Double?
var mineralKg: Double?
var basalMetabolicRateKcal: Double?
var visceralFatLevel: Double?
var inBodyScore: Double?
var waistHipRatio: Double?
var phaseAngleDegrees: Double?
```

Keep the initializer source-compatible by assigning the fields to `nil` in the
initializer; do not make every onboarding/default call site pass twelve values.
`AthleteProfileDraft` mirrors existing editable fields and these optional
measurements. `validationError` requires a finite positive height and weight,
birth year at least 1900, sessions 2...7, an allowed session-length value
(30/45/60/90), finite non-negative measurement values, PBF 0...100, and
positive waist–hip ratio/phase angle when supplied. Comparison treats equipment
and excluded-muscle arrays as sets so reordering does not mark a plan dirty.

- [ ] **Step 4: Implement atomic application and same-day weight upsert.**

`AthleteProfileStore.apply` must reject a non-nil `validationError`, compare the
old `profile.weightKg` before mutation, assign every draft property, set
`updatedAt = now`, and only when the weight actually changed:

```swift
let start = Calendar.isoUTC.startOfDay(for: now)
let existing = entries.first { Calendar.isoUTC.isDate($0.date, inSameDayAs: start) }
if let existing { existing.kg = draft.weightKg }
else { context.insert(BodyweightEntryModel(date: now, kg: draft.weightKg)) }
```

Finish with `try context.save()`. Do not mutate plan rows.

- [ ] **Step 5: Re-run the two focused test classes and ensure they pass.**

Run the command from Step 2. Expected: both classes pass.

### Task 2: Dedicated Profile summary and editor

**Files:**
- Create: `FitnessTracker/FitnessTracker/Features/Profile/AthleteProfileView.swift`
- Modify: `FitnessTracker/FitnessTracker/Features/Settings/SettingsView.swift`

**Interfaces:**

```swift
struct AthleteProfileView: View {
    let profile: UserProfile
    let catalog: CatalogStore?
    var onOpenPlan: (() -> Void)?
}
```

- [ ] **Step 1: Implement the overview using the approved information hierarchy.**

Create a scrollable `AthleteProfileView` with:

```swift
NavigationStack {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            heroCard
            trainingSetupCard
            bodyCompositionCard
            planActions
        }
    }
}
```

Use `GymTheme` surfaces and the selected accent. Hero has `Athlete Profile`, a
goal/experience label, weight and capacity summary, plus an accessible `Edit
profile` button. Body composition uses four compact tiles for weight, PBF,
SMM and BMR; show `—` with an `Add measurements` action if no reading exists.
Additional existing measurements appear in a disclosure row, never a giant
paragraph/card. Derive BMI safely only when height and weight are positive.

- [ ] **Step 2: Implement the editor form and save feedback.**

Present an `AthleteProfileEditorView` from `Edit profile`. Initialize its
`@State` draft from `AthleteProfileDraft(profile:)`. Use a `Form` with sections
Identity (height, birth year, sex), Training (Goal, experience, sessions,
session length, equipment, avoided muscles), and Body composition (all optional
fields in the spec). Every numeric input has a visible label, unit and
`.decimalPad`; empty optional fields save as `nil`, not zero. A Save button
uses `AthleteProfileStore.apply`; show the field-level validation error beside
the submit area, use success haptic + confirmation, and dismiss only after a
successful save.

- [ ] **Step 3: Add explicit plan actions.**

After a save that changes plan inputs, show an accent `Regenerate weekly plan`
button. While generating, disable the action and show `ProgressView`. Build the
active provider exactly as Settings does, call:

```swift
let outcome = await generateAndStore(
    context: profile.makeUserContext(),
    activeProfile: activeProvider,
    catalog: catalog,
    modelContext: context)
```

Then show `outcome.note`. If no catalog is available, disable the action with
an explanatory accessibility hint. Also include a secondary `Manage routines
and schedule` action that calls `onOpenPlan` after dismissing the Profile
sheet.

- [ ] **Step 4: Route Settings to the shared profile view.**

Replace Settings' duplicated `LabeledContent` profile rows with a single
`NavigationLink` to `AthleteProfileView(profile: p, catalog: catalog)`. Keep a
small subtitle containing goal and weekly capacity. Remove the old Settings
`regenerate(_:)` code and state only if no longer used by any other section.

### Task 3: Home entry, daily-check-in relocation, and integration review

**Files:**
- Modify: `FitnessTracker/FitnessTracker/Features/Home/HomeView.swift`
- Modify: `FitnessTracker/FitnessTracker/RootView.swift`

- [ ] **Step 1: Add Profile entry from Home without crowding the header.**

Replace the header's daily-check-in icon with a person icon labelled
`Profile`. Add `@State private var showProfile = false` and a full-screen
sheet:

```swift
.fullScreenCover(isPresented: $showProfile) {
    AthleteProfileView(profile: profile, catalog: catalog, onOpenPlan: onOpenPlan)
}
```

Keep the Coach unread badge and Settings action unchanged. The Profile icon has
an explicit accessibility label and 44pt touch target.

- [ ] **Step 2: Keep daily check-in discoverable in Home content.**

Add one compact, dismiss-free check-in action below the header/week strip when
today has no `DailyCheckinModel`: icon, `How are you feeling?`, one-line value
statement, and `Check in` button opening the existing `dailyCheckin` sheet.
When a row exists for today, show a compact `Today’s check-in` completion state
that reopens the same editor. Do not create a second persistence model or alter
`CheckinEntryView` save semantics.

- [ ] **Step 3: Let Profile open the Plan tab.**

Add `onOpenPlan: @escaping () -> Void` to `HomeView`. In Root pass
`{ selectedTab = .plan }`; this preserves the existing Plan tab and lets the
Profile action navigate there without reimplementing routine/schedule editing.

- [ ] **Step 4: Build and review in Simulator.**

Run:

```bash
xcodebuild build -quiet -project FitnessTracker/FitnessTracker.xcodeproj \
  -scheme FitnessTracker \
  -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A'
```

Install the result in simulator. Verify: Home Profile entry; Profile summary;
small and large body-composition states; editor save; Settings entry; profile
to Plan navigation; and Home check-in path. Capture screenshots for the user.

### Task 4: Focused regression gate and documentation

**Files:**
- Modify: `docs/HANDOFF.md`

- [ ] **Step 1: Run the focused profile regression group.**

Run:

```bash
xcodebuild test -quiet -project FitnessTracker/FitnessTracker.xcodeproj \
  -scheme FitnessTracker \
  -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' \
  -only-testing:FitnessTrackerTests/UserProfilePersistenceTests \
  -only-testing:FitnessTrackerTests/UserProfileMappingTests \
  -only-testing:FitnessTrackerTests/AthleteProfileDraftTests
```

- [ ] **Step 2: Record the completed Profile slice in Handoff.**

Add the Profile destination, manual composition snapshot, explicit
regeneration behavior, same-day weight timeline rule, and deferred InBody scan
ingestion to the relevant status/next-work section. Do not claim photo upload
or AI extraction exists.

- [ ] **Step 3: Run `git diff --check` and inspect status.**

Confirm the new Profile files and intentional integrations are the only changes
from this plan; do not stage, commit, discard, or modify unrelated working-tree
changes.

## Plan Review

- Spec coverage: Tasks 1–3 implement Profile persistence, editor, plan
  regeneration, bodyweight sync, Home/Settings entry, and visual requirements;
  Task 4 verifies and documents the slice. The explicit scan exclusions remain
  untouched.
- Placeholder scan: no implementation placeholders or deferred code paths are
  present; InBody is documented as a follow-up only.
- Type consistency: `AthleteProfileDraft`, `AthleteProfileStore.apply`, and
  `AthleteProfileView` names are defined once and reused consistently.
