# Proactive Notifications & Coach Outreach Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the proactive layer (`docs/specs/2026-09-06-proactive-notifications-design.md`):
a `ProactiveCoordinator` run on app-foreground that generates and schedules
the five §7 triggers (daily narration, weekly summary, InBody reminder,
check-in reaction, pattern nudge), plus the check-in entry screen and weekly
summary screen those need.

**Architecture:** iOS notifications can't call an LLM at fire time, so
`ProactiveCoordinator` generates text while the app is foregrounded and bakes
it into scheduled `UNNotificationRequest`s. Per-period idempotency via
`UserDefaults` day/week keys. Proactive coach messages persist as
`CoachNoteModel` and surface as Home cards (same visual language as the
existing `PendingObservationCard`/`SuggestionCard`). All LLM calls follow the
established coordinator pattern: background `Task`, silent no-op without a
provider, one `AICallRecord` each.

**Tech Stack:** Swift 6 `.v6`, Xcode 26, iOS 26, SwiftData, SwiftUI,
`UserNotifications`, Swift Testing, `FitnessCore` (`Metrics`, `CoachMemory`,
`LLMKit`, `FitnessDomain`, `ExerciseCatalog`).

**Spec:** `docs/specs/2026-09-06-proactive-notifications-design.md` (all
sections). Also read `docs/specs/2026-09-05-ai-coach-layer-v2-design.md` §7.

## Global Constraints

- Xcode 26 default `@MainActor` isolation for the app module. Coordinators
  touching `ModelContext` are `@MainActor`; pure DTO/prompt types are
  `nonisolated` (mirror `FinalizeDTO`/`FinalizePromptBuilder`).
- Every LLM call that runs writes one `AICallRecord` (call types
  `dailyNarration`, `weeklySummary`, `checkinReaction`, `patternNudge`),
  call-granular, mirroring `MemoryKeeperCoordinator`/`AskCoachCoordinator`.
- No LLM-backed item runs without a provider; the InBody reminder (no LLM)
  still runs. No proactive work ever blocks app launch — all calls are
  background `Task`s.
- **Do not use `removeAllPendingNotificationRequests()`.** The existing
  `SettingsView.scheduleWorkoutReminder` currently does — Task 10 changes it
  to per-identifier removal so proactive notifications survive. Every
  proactive notification uses a stable identifier (`proactive_daily`,
  `proactive_weekly`, `proactive_inbody`, `proactive_checkin`) so
  re-scheduling replaces rather than duplicates.
- Home reads `CoachNoteModel`/`WeeklySummaryModel` via `@Query` +
  Swift-side filter — **never** a boolean `#Predicate` (documented CoreData
  hang in this project; see `docs/HANDOFF.md`).
- Plain commits, no `Co-Authored-By` trailer. Do not push without being asked.
- End state: `xcodebuild test -scheme FitnessTracker -destination
  'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' -project
  FitnessTracker/FitnessTracker.xcodeproj 2>&1 | tail -30` green.

---

## File Structure

- `Models/ProactiveModels.swift` — **create**: `CoachNoteModel`,
  `WeeklySummaryModel`.
- `FitnessTrackerApp.swift` — modify: register both.
- `AI/ProactiveDTO.swift` — **create**: the four output DTOs.
- `AI/ProactivePromptBuilder.swift` — **create**: system/user builders for the
  four LLM calls.
- `AI/ProactiveCoordinator.swift` — **create**: `runDueChecks()`,
  `reactToCheckin(_:)`, the five trigger paths, notification scheduling,
  `UserDefaults` bookkeeping.
- `Features/Home/CheckinEntryView.swift` — **create**.
- `Features/Stats/WeeklySummaryView.swift` — **create**.
- `Features/Home/CoachNoteCard.swift` — **create**.
- `Features/Home/HomeView.swift` — modify: coach-note card list + check-in
  entry point + weekly-summary entry point.
- `RootView.swift` — modify: build `ProactiveCoordinator`, run
  `runDueChecks()` on scenePhase `.active`, route a notification tap to the
  weekly screen.
- `Features/Settings/SettingsView.swift` — modify: per-type toggles;
  per-identifier notification removal.
- Tests: `ProactiveModelsTests.swift`, `ProactiveDTOTests.swift`,
  `ProactivePromptBuilderTests.swift`, `ProactiveCoordinatorTests.swift` —
  create.

---

## Task 1: `CoachNoteModel` + `WeeklySummaryModel`

**Files:**
- Create: `Models/ProactiveModels.swift`
- Modify: `FitnessTrackerApp.swift`
- Test: `FitnessTrackerTests/ProactiveModelsTests.swift`

- [ ] **Step 1: Implement**

```swift
import Foundation
import SwiftData

/// A proactive message from the coach (design spec §5). `kindRaw` is
/// `"daily"` | `"weekly"` | `"checkin"` | `"pattern"`. Home shows unread ones
/// (`readAt == nil`) as cards.
@Model
final class CoachNoteModel {
    var id: UUID
    var kindRaw: String
    var text: String
    var createdAt: Date
    var readAt: Date?

    init(kindRaw: String, text: String, createdAt: Date = .now) {
        self.id = UUID()
        self.kindRaw = kindRaw
        self.text = text
        self.createdAt = createdAt
        self.readAt = nil
    }
}

/// One generated weekly recap (design spec §5). One row per ISO week; a
/// regeneration overwrites the existing row for that week.
@Model
final class WeeklySummaryModel {
    var weekStartDate: Date
    var headline: String
    var summaryBody: String
    var nextWeekFocus: String
    var generatedAt: Date

    init(weekStartDate: Date, headline: String, summaryBody: String, nextWeekFocus: String) {
        self.weekStartDate = weekStartDate
        self.headline = headline
        self.summaryBody = summaryBody
        self.nextWeekFocus = nextWeekFocus
        self.generatedAt = .now
    }
}
```

**Note for the implementer:** `body` is a reserved-ish name that collides
with SwiftUI in views that use this model — the field is `summaryBody`, not
`body`, on purpose. Keep it.

Register `CoachNoteModel.self, WeeklySummaryModel.self,` in
`FitnessTrackerApp.swift`'s `.modelContainer(for: [...])` list.

- [ ] **Step 2: Test**

```swift
import Testing
import SwiftData
@testable import FitnessTracker

@Suite struct ProactiveModelsTests {
    @Test func coachNoteDefaultsUnread() throws {
        let c = try ModelContainer(for: CoachNoteModel.self, WeeklySummaryModel.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(c)
        let note = CoachNoteModel(kindRaw: "daily", text: "Push day today.")
        ctx.insert(note)
        try ctx.save()
        let fetched = try ctx.fetch(FetchDescriptor<CoachNoteModel>())
        #expect(fetched.count == 1)
        #expect(fetched[0].readAt == nil)
    }

    @Test func weeklySummaryRoundTrips() throws {
        let c = try ModelContainer(for: CoachNoteModel.self, WeeklySummaryModel.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(c)
        ctx.insert(WeeklySummaryModel(weekStartDate: Date(), headline: "Solid week",
                                      summaryBody: "4 of 4 sessions.", nextWeekFocus: "Add pulling volume."))
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<WeeklySummaryModel>()).count == 1)
    }
}
```

- [ ] **Step 3: Build, focused test, full suite, commit**

```bash
git add FitnessTracker/FitnessTracker/Models/ProactiveModels.swift \
        FitnessTracker/FitnessTracker/FitnessTrackerApp.swift \
        FitnessTracker/FitnessTrackerTests/ProactiveModelsTests.swift
git commit -m "Add CoachNoteModel and WeeklySummaryModel"
```

---

## Task 2: `ProactiveDTO` + `ProactivePromptBuilder`

**Files:**
- Create: `AI/ProactiveDTO.swift`, `AI/ProactivePromptBuilder.swift`
- Test: `FitnessTrackerTests/ProactiveDTOTests.swift`,
  `FitnessTrackerTests/ProactivePromptBuilderTests.swift`

**Interfaces:**
- Produces: `DailyNarrationDTO { narration }`, `WeeklySummaryDTO { headline;
  body; nextWeekFocus }`, `CheckinReactionDTO { message }`, `PatternNudgeDTO
  { nudge }` (all `nonisolated struct … : Codable, Sendable`), and
  `nonisolated enum ProactivePromptBuilder` with `dailyNarrationSchema` /
  `weeklySummarySchema` / `checkinReactionSchema` / `patternNudgeSchema`
  (`JSONSchema`), `system() -> String` (one shared persona), and four
  `user…(…) -> String` builders.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import FitnessTracker

@Suite struct ProactiveDTOTests {
    @Test func decodesDailyNarration() throws {
        let dto = try JSONDecoder().decode(DailyNarrationDTO.self,
            from: Data(#"{"narration":"Push day — lead with dips."}"#.utf8))
        #expect(dto.narration.contains("dips"))
    }
    @Test func decodesWeeklySummary() throws {
        let dto = try JSONDecoder().decode(WeeklySummaryDTO.self,
            from: Data(#"{"headline":"Strong week","body":"4/4 sessions.","nextWeekFocus":"More rows."}"#.utf8))
        #expect(dto.headline == "Strong week")
        #expect(dto.nextWeekFocus == "More rows.")
    }
    @Test func decodesCheckinReaction() throws {
        let dto = try JSONDecoder().decode(CheckinReactionDTO.self,
            from: Data(#"{"message":"Take it easy on legs today."}"#.utf8))
        #expect(!dto.message.isEmpty)
    }
    @Test func decodesPatternNudge() throws {
        let dto = try JSONDecoder().decode(PatternNudgeDTO.self,
            from: Data(#"{"nudge":"You've skipped pull day three weeks running."}"#.utf8))
        #expect(!dto.nudge.isEmpty)
    }
}
```

```swift
import Testing
@testable import FitnessTracker

@Suite struct ProactivePromptBuilderTests {
    @Test func systemPromptEstablishesCoachVoice() {
        #expect(ProactivePromptBuilder.system().lowercased().contains("trainer")
             || ProactivePromptBuilder.system().lowercased().contains("coach"))
    }
    @Test func dailyUserPromptIncludesSessionAndRecovery() {
        let p = ProactivePromptBuilder.userDailyNarration(
            sessionLabel: "Push Day", exerciseNames: ["Bench Press", "Dips"],
            recoveryDigest: "chest: fresh", memoryDigest: "")
        #expect(p.contains("Push Day"))
        #expect(p.contains("Dips"))
        #expect(p.contains("chest: fresh"))
    }
    @Test func weeklyUserPromptIncludesTheNumbers() {
        let p = ProactivePromptBuilder.userWeeklySummary(
            sessionsCompleted: 4, plannedPerWeek: 4, streakWeeks: 3,
            muscleCoverageDigest: "back undertrained", prCount: 2, memoryDigest: "")
        #expect(p.contains("4"))
        #expect(p.contains("back undertrained"))
    }
    @Test func checkinUserPromptIncludesRatings() {
        let p = ProactivePromptBuilder.userCheckinReaction(
            soreness: 8, sleepQuality: 4, note: "quads wrecked",
            recentSessionsDigest: "legs Monday", memoryDigest: "")
        #expect(p.contains("8"))
        #expect(p.contains("quads wrecked"))
    }
    @Test func patternUserPromptIncludesTheStatement() {
        let p = ProactivePromptBuilder.userPatternNudge(
            patternStatement: "Skips pull day when busy",
            recentSessionsDigest: "push, push, legs", memoryDigest: "")
        #expect(p.contains("Skips pull day when busy"))
    }
}
```

- [ ] **Step 2: Run to verify they fail**

- [ ] **Step 3: Implement `ProactiveDTO.swift`**

```swift
import Foundation

nonisolated struct DailyNarrationDTO: Codable, Sendable { let narration: String }
nonisolated struct WeeklySummaryDTO: Codable, Sendable {
    let headline: String
    let body: String
    let nextWeekFocus: String
}
nonisolated struct CheckinReactionDTO: Codable, Sendable { let message: String }
nonisolated struct PatternNudgeDTO: Codable, Sendable { let nudge: String }
```

- [ ] **Step 4: Implement `ProactivePromptBuilder.swift`**

```swift
import Foundation
import LLMKit

nonisolated enum ProactivePromptBuilder {
    static let dailyNarrationSchema = JSONSchema(json: #"{"narration": "string — one or two sentences"}"#)
    static let weeklySummarySchema = JSONSchema(json: #"{"headline": "string — short", "body": "string — 2-4 sentences", "nextWeekFocus": "string — one sentence"}"#)
    static let checkinReactionSchema = JSONSchema(json: #"{"message": "string — one or two sentences"}"#)
    static let patternNudgeSchema = JSONSchema(json: #"{"nudge": "string — one or two sentences"}"#)

    static func system() -> String {
        """
        You are an experienced, direct personal trainer reaching out to your \
        athlete between sessions. Keep it short and specific — cite an actual \
        exercise, muscle, number, or day. No filler, no generic \
        encouragement. Respond only in the required JSON shape.
        """
    }

    static func userDailyNarration(sessionLabel: String, exerciseNames: [String],
                                   recoveryDigest: String, memoryDigest: String) -> String {
        [
            "Today's session: \(sessionLabel) — \(exerciseNames.joined(separator: ", "))",
            recoveryDigest.isEmpty ? "" : "Recovery right now:\n\(recoveryDigest)",
            memoryDigest.isEmpty ? "" : "What you know about this athlete:\n\(memoryDigest)",
            "Write a one-or-two-sentence heads-up for today."
        ].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    static func userWeeklySummary(sessionsCompleted: Int, plannedPerWeek: Int, streakWeeks: Int,
                                  muscleCoverageDigest: String, prCount: Int, memoryDigest: String) -> String {
        [
            "This week: \(sessionsCompleted)/\(plannedPerWeek) sessions completed, \(streakWeeks)-week streak, \(prCount) new PRs.",
            muscleCoverageDigest.isEmpty ? "" : "Muscle coverage:\n\(muscleCoverageDigest)",
            memoryDigest.isEmpty ? "" : "What you know about this athlete:\n\(memoryDigest)",
            "Write the week's recap: a short headline, a 2-4 sentence body, and one sentence on what to prioritize next week."
        ].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    static func userCheckinReaction(soreness: Int?, sleepQuality: Int?, note: String?,
                                    recentSessionsDigest: String, memoryDigest: String) -> String {
        var lines = ["The athlete just logged a check-in:"]
        if let s = soreness { lines.append("- Soreness: \(s)/10") }
        if let q = sleepQuality { lines.append("- Sleep quality: \(q)/10") }
        if let n = note, !n.isEmpty { lines.append("- Note: \(n)") }
        return [
            lines.joined(separator: "\n"),
            recentSessionsDigest.isEmpty ? "" : "Recent sessions:\n\(recentSessionsDigest)",
            memoryDigest.isEmpty ? "" : "What you know about this athlete:\n\(memoryDigest)",
            "React in one or two sentences — a concrete adjustment or reassurance, not generic advice."
        ].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    static func userPatternNudge(patternStatement: String, recentSessionsDigest: String, memoryDigest: String) -> String {
        [
            "You've noticed this pattern in the athlete: \(patternStatement)",
            recentSessionsDigest.isEmpty ? "" : "Recent sessions:\n\(recentSessionsDigest)",
            memoryDigest.isEmpty ? "" : "What else you know:\n\(memoryDigest)",
            "Nudge them about it in one or two sentences — name the pattern and one thing to do about it."
        ].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}
```

- [ ] **Step 5: Run tests, then commit**

```bash
git add FitnessTracker/FitnessTracker/AI/ProactiveDTO.swift \
        FitnessTracker/FitnessTracker/AI/ProactivePromptBuilder.swift \
        FitnessTracker/FitnessTrackerTests/ProactiveDTOTests.swift \
        FitnessTracker/FitnessTrackerTests/ProactivePromptBuilderTests.swift
git commit -m "Add ProactiveDTO and ProactivePromptBuilder"
```

---

## Task 3: `ProactiveCoordinator` — core, daily narration, InBody

**Files:**
- Create: `AI/ProactiveCoordinator.swift`
- Test: `FitnessTrackerTests/ProactiveCoordinatorTests.swift`

**Interfaces:**
- Produces: `@MainActor struct ProactiveCoordinator { let context:
  ModelContext; let catalog: CatalogStore; let provider: (any LLMProvider)?;
  let activeProfile: ProviderProfile?; let settings: ProactiveSettings; func
  runDueChecks() async; func reactToCheckin(_ checkin: DailyCheckinModel)
  async }` (Task 6 adds `reactToCheckin`'s body; Tasks 4/5 add the weekly and
  pattern paths). `struct ProactiveSettings { var dailyOn, weeklyOn,
  inbodyOn, checkinOn, patternOn: Bool; var reminderHour, reminderMinute: Int
  }` — built by `RootView`/`Settings` from `@AppStorage`.

- [ ] **Step 1: Write the failing tests** (core + daily + InBody only)

```swift
import Testing
import SwiftData
import Foundation
import FitnessDomain
import ExerciseCatalog
@testable import FitnessTracker

@MainActor
@Suite struct ProactiveCoordinatorTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: UserProfile.self, StoredPlan.self, ProviderProfile.self, AICallRecord.self,
            CompletedSessionModel.self, CompletedEntryModel.self, LoggedSetModel.self,
            BodyweightEntryModel.self, DailyCheckinModel.self, ObservationModel.self,
            PersonalRecordModel.self, CoachMemoryModel.self,
            CoachNoteModel.self, WeeklySummaryModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
    private func exercise(_ id: String) -> Exercise {
        Exercise(id: id, name: id.capitalized, primaryMuscle: .chest, secondaryMuscles: [],
                 equipment: .barbell, mechanic: .compound, force: .push,
                 difficulty: .intermediate, isUnilateral: false, instructions: [], imagePaths: [])
    }
    private func catalog() -> CatalogStore { CatalogStore(exercises: [exercise("bench"), exercise("dips")]) }
    private func settings(all: Bool = true) -> ProactiveSettings {
        ProactiveSettings(dailyOn: all, weeklyOn: all, inbodyOn: all, checkinOn: all, patternOn: all,
                          reminderHour: 8, reminderMinute: 0)
    }
    private func seedPlan(in ctx: ModelContext) throws {
        let plan = WeeklyPlan(weekStartDate: Date(), source: .ruleEngine, rationale: "t",
            sessions: [PlannedSession(id: UUID(), order: 0, focusMuscles: [.chest], items: [
                PlannedItem(exerciseID: "bench", targetSets: 3, targetReps: RepRange(min: 6, max: 8),
                            targetLoadKg: 60, restSeconds: 90, coachNote: ""),
                PlannedItem(exerciseID: "dips", targetSets: 3, targetReps: RepRange(min: 8, max: 12),
                            targetLoadKg: nil, restSeconds: 90, coachNote: "")
            ])], weeklyVolumeTargets: [])
        ctx.insert(try StoredPlan(plan: plan, hadValidationIssues: false))
        try ctx.save()
    }

    @Test func dailyNarrationWritesACoachNoteWhenDue() async throws {
        let ctx = ModelContext(try container())
        try seedPlan(in: ctx)
        UserDefaults.standard.removeObject(forKey: "proactive.daily.lastGeneratedDay")
        let final = #"{"decision":"final","final":{"narration":"Push day — lead with dips, chest is fresh."}}"#
        let provider = StubLLMProvider(responses: [.success(final)])
        let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: provider,
                                         activeProfile: nil, settings: settings())

        await coord.runDueChecks()

        let notes = try ctx.fetch(FetchDescriptor<CoachNoteModel>())
        #expect(notes.contains { $0.kindRaw == "daily" })
    }

    @Test func dailyNarrationSkippedWhenAlreadyGeneratedToday() async throws {
        let ctx = ModelContext(try container())
        try seedPlan(in: ctx)
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        UserDefaults.standard.set(df.string(from: Date()), forKey: "proactive.daily.lastGeneratedDay")
        let provider = StubLLMProvider(responses: [])
        let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: provider,
                                         activeProfile: nil, settings: settings())

        await coord.runDueChecks()

        #expect(try ctx.fetch(FetchDescriptor<CoachNoteModel>()).filter { $0.kindRaw == "daily" }.isEmpty)
    }

    @Test func noProviderSkipsLLMItems() async throws {
        let ctx = ModelContext(try container())
        try seedPlan(in: ctx)
        UserDefaults.standard.removeObject(forKey: "proactive.daily.lastGeneratedDay")
        let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: nil,
                                         activeProfile: nil, settings: settings())

        await coord.runDueChecks()

        #expect(try ctx.fetch(FetchDescriptor<CoachNoteModel>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<AICallRecord>()).isEmpty)
    }

    @Test func dailyToggleOffSkipsIt() async throws {
        let ctx = ModelContext(try container())
        try seedPlan(in: ctx)
        UserDefaults.standard.removeObject(forKey: "proactive.daily.lastGeneratedDay")
        let provider = StubLLMProvider(responses: [])
        var s = settings(); s.dailyOn = false
        let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: provider,
                                         activeProfile: nil, settings: s)

        await coord.runDueChecks()

        #expect(try ctx.fetch(FetchDescriptor<CoachNoteModel>()).filter { $0.kindRaw == "daily" }.isEmpty)
    }
}
```

**Note for the implementer:** these tests touch real `UserDefaults.standard`.
Use a distinctive key prefix (`proactive.…` as specified) and have each test
clear the key it depends on in its own body (shown above). Do not add a
custom `UserDefaults` suite unless a test proves flaky — the keys are
namespaced enough that parallel test runs on the same key are the only risk,
and Swift Testing runs a suite's tests serially by default within the suite.

- [ ] **Step 2: Run to verify they fail**

- [ ] **Step 3: Implement `ProactiveCoordinator.swift`** (core + daily + InBody; weekly/pattern/checkin are stubs Tasks 4-6 fill)

```swift
import Foundation
import SwiftData
import UserNotifications
import FitnessDomain
import ExerciseCatalog
import Metrics
import CoachMemory
import LLMKit

nonisolated struct ProactiveSettings: Sendable {
    var dailyOn: Bool
    var weeklyOn: Bool
    var inbodyOn: Bool
    var checkinOn: Bool
    var patternOn: Bool
    var reminderHour: Int
    var reminderMinute: Int
}

/// The proactive layer (design spec §3). Run from `RootView` on every
/// app-foreground. Generates LLM text while the app is open and bakes it into
/// scheduled notifications, since iOS can't call an LLM at fire time.
@MainActor
struct ProactiveCoordinator {
    let context: ModelContext
    let catalog: CatalogStore
    let provider: (any LLMProvider)?
    let activeProfile: ProviderProfile?
    let settings: ProactiveSettings

    private let notificationCenter = UNUserNotificationCenter.current()
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.calendar = .isoUTC; return f
    }()

    func runDueChecks() async {
        if settings.inbodyOn { scheduleInBodyReminderIfNeeded() }
        else { notificationCenter.removePendingNotificationRequests(withIdentifiers: ["proactive_inbody"]) }

        guard provider != nil else { return }

        if settings.dailyOn, isDailyDue() { await generateDailyNarration() }
        if settings.weeklyOn, isWeeklyDue() { await generateWeeklySummary() }      // Task 4
        if settings.patternOn { await runPatternNudges() }                        // Task 5
    }

    // MARK: - Daily narration (#6)

    private func isDailyDue() -> Bool {
        UserDefaults.standard.string(forKey: "proactive.daily.lastGeneratedDay") != Self.dayFormatter.string(from: .now)
    }

    private func generateDailyNarration() async {
        guard let provider,
              let plan = mostRecentPlan(),
              let session = todaysOrNextSession(in: plan)
        else { return }

        let sessionLabel = session.focusMuscles.map { $0.rawValue.capitalized }.joined(separator: "/") + " Day"
        let exerciseNames = session.items.compactMap { catalog.exercise(id: $0.exerciseID)?.name }
        let recoveryDigest = recoveryDigest()
        let memoryDigest = memoryDigest()

        let system = ProactivePromptBuilder.system()
        let user = ProactivePromptBuilder.userDailyNarration(
            sessionLabel: sessionLabel, exerciseNames: exerciseNames,
            recoveryDigest: recoveryDigest, memoryDigest: memoryDigest)

        do {
            let result: ToolLoopResult<DailyNarrationDTO> = try await ToolLoopRunner().run(
                system: system, initialUser: user,
                finalSchema: ProactivePromptBuilder.dailyNarrationSchema,
                tools: ToolRegistry(tools: []), provider: provider)
            recordCalls(result.calls, callType: "dailyNarration")
            let text = result.value.narration
            context.insert(CoachNoteModel(kindRaw: "daily", text: text))
            try? context.save()
            scheduleDaily(body: text)
            UserDefaults.standard.set(Self.dayFormatter.string(from: .now), forKey: "proactive.daily.lastGeneratedDay")
        } catch ToolLoopError.exceededMaxIterations(let calls) {
            recordCalls(calls, callType: "dailyNarration")
        } catch { return }
    }

    private func scheduleDaily(body: String) {
        let content = UNMutableNotificationContent()
        content.title = "From your coach"
        content.body = body
        content.sound = .default
        var dc = DateComponents(); dc.hour = settings.reminderHour; dc.minute = settings.reminderMinute
        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ["proactive_daily"])
        notificationCenter.add(UNNotificationRequest(identifier: "proactive_daily", content: content, trigger: trigger))
    }

    // MARK: - InBody reminder (#8) — no LLM

    private func scheduleInBodyReminderIfNeeded() {
        notificationCenter.getPendingNotificationRequests { requests in
            guard !requests.contains(where: { $0.identifier == "proactive_inbody" }) else { return }
            let content = UNMutableNotificationContent()
            content.title = "InBody scan due"
            content.body = "It's been about 5 weeks — take a scan and tell your coach the numbers in chat."
            content.sound = .default
            let fiveWeeks: TimeInterval = 5 * 7 * 24 * 3600
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fiveWeeks, repeats: true)
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "proactive_inbody", content: content, trigger: trigger))
        }
    }

    /// Call when a body-composition observation is confirmed so the 5-week
    /// clock restarts. (Wired in a later task / by ObservationModel confirm UI.)
    func resetInBodyReminder() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ["proactive_inbody"])
        if settings.inbodyOn { scheduleInBodyReminderIfNeeded() }
    }

    // MARK: - Weekly (#7) — Task 4 fills this

    func isWeeklyDue() -> Bool { false }
    private func generateWeeklySummary() async {}

    // MARK: - Pattern nudge (#10) — Task 5 fills this

    private func runPatternNudges() async {}

    // MARK: - Check-in reaction (#9) — Task 6 fills this

    func reactToCheckin(_ checkin: DailyCheckinModel) async {}

    // MARK: - Shared helpers

    private func mostRecentPlan() -> WeeklyPlan? {
        (try? context.fetch(FetchDescriptor<StoredPlan>(sortBy: [SortDescriptor(\.generatedAt, order: .reverse)])))?
            .first.flatMap { try? $0.decodedPlan() }
    }

    /// Today's planned session if it hasn't been completed yet, else the next
    /// not-yet-completed one in `order`.
    private func todaysOrNextSession(in plan: WeeklyPlan) -> PlannedSession? {
        let started = Set(((try? context.fetch(FetchDescriptor<CompletedSessionModel>())) ?? [])
            .compactMap(\.plannedSessionID))
        return plan.sessions.sorted { $0.order < $1.order }.first { !started.contains($0.id) }
    }

    private func recoveryDigest() -> String {
        let snapshots = ((try? context.fetch(FetchDescriptor<CompletedSessionModel>())) ?? []).map { $0.toSnapshot() }
        let statuses = RecoveryModel.computeRecovery(from: snapshots, catalog: catalog, now: .now)
        return statuses
            .sorted { $0.value.fatigueScore < $1.value.fatigueScore }
            .prefix(4)
            .map { "\($0.key.rawValue): \($0.value.state.rawValue)" }
            .joined(separator: ", ")
    }

    private func memoryDigest() -> String {
        let mems = ((try? context.fetch(FetchDescriptor<CoachMemoryModel>())) ?? []).map { $0.toDomain() }
        return MemoryRecall.select(from: mems, context: RecallContext(), now: .now).digest
    }

    func recordCalls(_ calls: [CallOutcome], callType: String) {
        guard !calls.isEmpty else { return }
        for call in calls {
            let cost: Double
            if let p = activeProfile {
                cost = AICallRecord.cost(inputTokens: call.inputTokens, outputTokens: call.outputTokens,
                                         cachedTokens: call.cachedTokens,
                                         pricePerMTokIn: p.pricePerMTokIn, pricePerMTokOut: p.pricePerMTokOut,
                                         pricePerMTokCached: p.pricePerMTokCached)
            } else { cost = 0 }
            context.insert(AICallRecord(callType: callType,
                providerDisplayName: activeProfile?.displayName ?? "—",
                modelID: activeProfile?.modelID ?? "—",
                inputTokens: call.inputTokens, outputTokens: call.outputTokens,
                cachedTokens: call.cachedTokens, costUSD: cost,
                success: call.succeeded, usedFallback: false))
        }
        try? context.save()
    }
}
```

**Note for the implementer:** verify against real source before trusting
verbatim — `RecoveryModel.computeRecovery`'s signature (checked in prior
plans: `(from: [CompletedSessionSnapshot], catalog:, now:)`),
`MuscleRecoveryStatus`'s `.state`/`.fatigueScore` fields, `CompletedSessionModel.toSnapshot()`,
`ToolLoopRunner`/`ToolLoopResult`/`CallOutcome`/`ToolLoopError`,
`StoredPlan.decodedPlan()`, `Calendar.isoUTC`. The `ToolLoopRunner`-with-empty-registry
pattern for a tool-less structured call is the one `ChatSummarizer` established
— reuse it, don't call `provider.complete` directly (the `StubLLMProvider`
test fixtures use the `ToolLoopTurn` envelope).

- [ ] **Step 4: Run tests, then commit**

```bash
git add FitnessTracker/FitnessTracker/AI/ProactiveCoordinator.swift \
        FitnessTracker/FitnessTrackerTests/ProactiveCoordinatorTests.swift
git commit -m "Add ProactiveCoordinator: core, daily narration, InBody reminder"
```

---

## Task 4: `ProactiveCoordinator` — weekly summary path

**Files:**
- Modify: `AI/ProactiveCoordinator.swift`
- Modify (extend): `FitnessTrackerTests/ProactiveCoordinatorTests.swift`

- [ ] **Step 1: Add the failing test**

```swift
@Test func weeklySummaryWritesModelAndNoteWhenDue() async throws {
    let ctx = ModelContext(try container())
    try seedPlan(in: ctx)
    UserDefaults.standard.removeObject(forKey: "proactive.weekly.lastWeekStart")
    UserDefaults.standard.set(Self.todayString(), forKey: "proactive.daily.lastGeneratedDay") // isolate: daily not due
    let final = #"{"decision":"final","final":{"headline":"Solid week","body":"3 of 4 sessions, chest twice.","nextWeekFocus":"Hit back harder."}}"#
    let provider = StubLLMProvider(responses: [.success(final)])
    var s = settings(); s.dailyOn = false; s.patternOn = false
    let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: provider,
                                     activeProfile: nil, settings: s)

    await coord.runDueChecks()

    #expect(try ctx.fetch(FetchDescriptor<WeeklySummaryModel>()).count == 1)
    #expect(try ctx.fetch(FetchDescriptor<CoachNoteModel>()).contains { $0.kindRaw == "weekly" })
}

@Test func weeklySummarySkippedWhenAlreadyDoneThisWeek() async throws {
    let ctx = ModelContext(try container())
    try seedPlan(in: ctx)
    let weekStart = Calendar.isoUTC.dateInterval(of: .weekOfYear, for: .now)!.start
    let iso = ISO8601DateFormatter().string(from: weekStart)
    UserDefaults.standard.set(iso, forKey: "proactive.weekly.lastWeekStart")
    let provider = StubLLMProvider(responses: [])
    var s = settings(); s.dailyOn = false; s.patternOn = false
    let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: provider,
                                     activeProfile: nil, settings: s)

    await coord.runDueChecks()

    #expect(try ctx.fetch(FetchDescriptor<WeeklySummaryModel>()).isEmpty)
}
```

**Note for the implementer:** add a `static func todayString()` test helper
if you use one, or inline the `DateFormatter` as in Task 3's tests — keep it
consistent with what's already in the file.

- [ ] **Step 2: Implement** — replace the `isWeeklyDue()`/`generateWeeklySummary()`
stubs:

```swift
func isWeeklyDue() -> Bool {
    guard let weekStart = Calendar.isoUTC.dateInterval(of: .weekOfYear, for: .now)?.start else { return false }
    let iso = ISO8601DateFormatter().string(from: weekStart)
    return UserDefaults.standard.string(forKey: "proactive.weekly.lastWeekStart") != iso
}

private func generateWeeklySummary() async {
    guard let provider, let weekStart = Calendar.isoUTC.dateInterval(of: .weekOfYear, for: .now)?.start else { return }
    let priorWeek = Calendar.isoUTC.date(byAdding: .weekOfYear, value: -1, to: weekStart)!
    let priorInterval = DateInterval(start: priorWeek, end: weekStart)

    let allSessions = ((try? context.fetch(FetchDescriptor<CompletedSessionModel>())) ?? [])
    let weekSessions = allSessions.filter { $0.finishedAt.map(priorInterval.contains) ?? false }
    let snapshots = allSessions.map { $0.toSnapshot() }
    let plannedPerWeek = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first?.sessionsPerWeek ?? 3
    let streak = StreakCalculator.computeSummary(from: snapshots, plannedPerWeek: plannedPerWeek).currentStreakWeeks
    let prCount = ((try? context.fetch(FetchDescriptor<PersonalRecordModel>())) ?? [])
        .filter { priorInterval.contains($0.date) }.count

    // Muscle coverage over the prior week (reuse the EffectiveSetItem shape the
    // other coordinators build).
    var items: [MuscleBalanceModel.EffectiveSetItem] = []
    for s in weekSessions {
        for e in s.entries where !e.skipped {
            guard let ex = catalog.exercise(id: e.exerciseID) else { continue }
            let doneSets = e.sets.filter { !$0.isWarmup }.count
            if doneSets > 0 { items.append(.init(exercise: ex, sets: doneSets)) }
        }
    }
    let (_, missed) = MuscleBalanceModel.rankOf(load: MuscleBalanceModel.loadOf(items: items))
    let coverageDigest = missed.isEmpty ? "all major muscles trained" : "undertrained: \(missed.joined(separator: ", "))"

    let system = ProactivePromptBuilder.system()
    let user = ProactivePromptBuilder.userWeeklySummary(
        sessionsCompleted: weekSessions.count, plannedPerWeek: plannedPerWeek, streakWeeks: streak,
        muscleCoverageDigest: coverageDigest, prCount: prCount, memoryDigest: memoryDigest())

    do {
        let result: ToolLoopResult<WeeklySummaryDTO> = try await ToolLoopRunner().run(
            system: system, initialUser: user, finalSchema: ProactivePromptBuilder.weeklySummarySchema,
            tools: ToolRegistry(tools: []), provider: provider)
        recordCalls(result.calls, callType: "weeklySummary")
        let dto = result.value

        // one row per week — replace an existing one for the same weekStart
        let existing = ((try? context.fetch(FetchDescriptor<WeeklySummaryModel>())) ?? [])
            .first { Calendar.isoUTC.isDate($0.weekStartDate, inSameDayAs: weekStart) }
        if let existing {
            existing.headline = dto.headline; existing.summaryBody = dto.body
            existing.nextWeekFocus = dto.nextWeekFocus; existing.generatedAt = .now
        } else {
            context.insert(WeeklySummaryModel(weekStartDate: weekStart, headline: dto.headline,
                summaryBody: dto.body, nextWeekFocus: dto.nextWeekFocus))
        }
        context.insert(CoachNoteModel(kindRaw: "weekly", text: dto.headline))
        try? context.save()
        scheduleWeekly(body: dto.headline)
        UserDefaults.standard.set(ISO8601DateFormatter().string(from: weekStart), forKey: "proactive.weekly.lastWeekStart")
    } catch ToolLoopError.exceededMaxIterations(let calls) {
        recordCalls(calls, callType: "weeklySummary")
    } catch { return }
}

private func scheduleWeekly(body: String) {
    let content = UNMutableNotificationContent()
    content.title = "Your week in review"
    content.body = body
    content.sound = .default
    content.userInfo = ["proactive": "weekly"]
    // ~1 minute out — the summary is already generated and persisted; the
    // notification is just the ping to go read it.
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
    notificationCenter.removePendingNotificationRequests(withIdentifiers: ["proactive_weekly"])
    notificationCenter.add(UNNotificationRequest(identifier: "proactive_weekly", content: content, trigger: trigger))
}
```

**Note for the implementer:** verify `StreakCalculator.computeSummary`'s
return type has `currentStreakWeeks` (`FitnessCore/Sources/Metrics/StreakCalculator.swift`),
`MuscleBalanceModel.rankOf`/`loadOf`/`EffectiveSetItem` (used in the
Suggestion Cards plan), and `UserProfile.sessionsPerWeek`. `isWeeklyDue()`
was declared non-private in Task 3 for testability — keep it that way.

- [ ] **Step 3: Run tests, then commit**

```bash
git add FitnessTracker/FitnessTracker/AI/ProactiveCoordinator.swift \
        FitnessTracker/FitnessTrackerTests/ProactiveCoordinatorTests.swift
git commit -m "Add weekly summary generation to ProactiveCoordinator"
```

---

## Task 5: `ProactiveCoordinator` — pattern nudge path

**Files:**
- Modify: `AI/ProactiveCoordinator.swift`
- Modify (extend): `FitnessTrackerTests/ProactiveCoordinatorTests.swift`

- [ ] **Step 1: Add the failing test**

```swift
@Test func patternNudgeWritesANoteForAHighConfidenceResponsePattern() async throws {
    let ctx = ModelContext(try container())
    UserDefaults.standard.set(Self.todayString(), forKey: "proactive.daily.lastGeneratedDay")
    let weekIso = ISO8601DateFormatter().string(from: Calendar.isoUTC.dateInterval(of: .weekOfYear, for: .now)!.start)
    UserDefaults.standard.set(weekIso, forKey: "proactive.weekly.lastWeekStart")
    let mem = CoachMemoryModel(kindRaw: "responsePattern", statement: "Skips pull day when the week is busy",
                               confidence: 0.8, sourceKind: "agent", createdAt: .now, lastConfirmedAt: .now)
    ctx.insert(mem)
    try ctx.save()
    UserDefaults.standard.removeObject(forKey: "proactive.patternNudge.\(mem.id.uuidString)")
    let final = #"{"decision":"final","final":{"nudge":"You've skipped pull day 3 weeks running — do it first this week."}}"#
    let provider = StubLLMProvider(responses: [.success(final)])
    var s = settings(); s.dailyOn = false; s.weeklyOn = false
    let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: provider,
                                     activeProfile: nil, settings: s)

    await coord.runDueChecks()

    #expect(try ctx.fetch(FetchDescriptor<CoachNoteModel>()).contains { $0.kindRaw == "pattern" })
}

@Test func patternNudgeSkipsLowConfidenceAndRecentlyNudged() async throws {
    let ctx = ModelContext(try container())
    UserDefaults.standard.set(Self.todayString(), forKey: "proactive.daily.lastGeneratedDay")
    UserDefaults.standard.set(ISO8601DateFormatter().string(from: Calendar.isoUTC.dateInterval(of: .weekOfYear, for: .now)!.start),
                              forKey: "proactive.weekly.lastWeekStart")
    let lowConf = CoachMemoryModel(kindRaw: "responsePattern", statement: "Weak", confidence: 0.4,
                                   sourceKind: "agent", createdAt: .now, lastConfirmedAt: .now)
    let nudged = CoachMemoryModel(kindRaw: "responsePattern", statement: "Recently nudged", confidence: 0.9,
                                  sourceKind: "agent", createdAt: .now, lastConfirmedAt: .now)
    ctx.insert(lowConf); ctx.insert(nudged); try ctx.save()
    UserDefaults.standard.set(ISO8601DateFormatter().string(from: .now),
                              forKey: "proactive.patternNudge.\(nudged.id.uuidString)")
    let provider = StubLLMProvider(responses: [])
    var s = settings(); s.dailyOn = false; s.weeklyOn = false
    let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: provider,
                                     activeProfile: nil, settings: s)

    await coord.runDueChecks()

    #expect(try ctx.fetch(FetchDescriptor<CoachNoteModel>()).filter { $0.kindRaw == "pattern" }.isEmpty)
}
```

- [ ] **Step 2: Implement** — replace the `runPatternNudges()` stub:

```swift
private func runPatternNudges() async {
    guard let provider else { return }
    let candidates = ((try? context.fetch(FetchDescriptor<CoachMemoryModel>())) ?? [])
        .filter { $0.kindRaw == "responsePattern" && $0.confidence >= 0.6 && $0.supersededBy == nil && !$0.retiredByCap }
        .filter { mem in
            let key = "proactive.patternNudge.\(mem.id.uuidString)"
            guard let s = UserDefaults.standard.string(forKey: key),
                  let last = ISO8601DateFormatter().date(from: s) else { return true }
            return Date().timeIntervalSince(last) > 14 * 24 * 3600
        }
        .sorted { $0.confidence > $1.confidence }

    guard let target = candidates.first else { return }

    let recentDigest = recentSessionsDigest(limit: 5)
    let system = ProactivePromptBuilder.system()
    let user = ProactivePromptBuilder.userPatternNudge(
        patternStatement: target.statement, recentSessionsDigest: recentDigest, memoryDigest: memoryDigest())

    do {
        let result: ToolLoopResult<PatternNudgeDTO> = try await ToolLoopRunner().run(
            system: system, initialUser: user, finalSchema: ProactivePromptBuilder.patternNudgeSchema,
            tools: ToolRegistry(tools: []), provider: provider)
        recordCalls(result.calls, callType: "patternNudge")
        context.insert(CoachNoteModel(kindRaw: "pattern", text: result.value.nudge))
        try? context.save()
        UserDefaults.standard.set(ISO8601DateFormatter().string(from: .now),
                                  forKey: "proactive.patternNudge.\(target.id.uuidString)")
    } catch ToolLoopError.exceededMaxIterations(let calls) {
        recordCalls(calls, callType: "patternNudge")
    } catch { return }
}

private func recentSessionsDigest(limit: Int) -> String {
    ((try? context.fetch(FetchDescriptor<CompletedSessionModel>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))) ?? [])
        .prefix(limit)
        .map { s in
            let day = Self.dayFormatter.string(from: s.startedAt)
            let names = s.entries.sorted { $0.performedOrder < $1.performedOrder }
                .compactMap { catalog.exercise(id: $0.exerciseID)?.name }.prefix(3)
            return "\(day): \(names.joined(separator: ", "))"
        }
        .joined(separator: "\n")
}
```

**Note for the implementer:** confirm `CoachMemoryModel`'s real field names
(`kindRaw`, `statement`, `confidence`, `supersededBy`, `retiredByCap`) —
they were read in the memory-keeper plan.

- [ ] **Step 3: Run tests, then commit**

```bash
git add FitnessTracker/FitnessTracker/AI/ProactiveCoordinator.swift \
        FitnessTracker/FitnessTrackerTests/ProactiveCoordinatorTests.swift
git commit -m "Add pattern-nudge generation to ProactiveCoordinator"
```

---

## Task 6: `ProactiveCoordinator` — check-in reaction path

**Files:**
- Modify: `AI/ProactiveCoordinator.swift`
- Modify (extend): `FitnessTrackerTests/ProactiveCoordinatorTests.swift`

- [ ] **Step 1: Add the failing tests**

```swift
@Test func checkinReactionFiresAboveSorenessThreshold() async throws {
    let ctx = ModelContext(try container())
    let checkin = DailyCheckinModel(date: Date())
    checkin.soreness = 8
    checkin.note = "quads destroyed"
    ctx.insert(checkin); try ctx.save()
    let final = #"{"decision":"final","final":{"message":"Skip legs today, walk instead."}}"#
    let provider = StubLLMProvider(responses: [.success(final)])
    let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: provider,
                                     activeProfile: nil, settings: settings())

    await coord.reactToCheckin(checkin)

    #expect(try ctx.fetch(FetchDescriptor<CoachNoteModel>()).contains { $0.kindRaw == "checkin" })
}

@Test func checkinReactionSkippedBelowThreshold() async throws {
    let ctx = ModelContext(try container())
    let checkin = DailyCheckinModel(date: Date())
    checkin.soreness = 3
    checkin.sleepQuality = 8
    ctx.insert(checkin); try ctx.save()
    let provider = StubLLMProvider(responses: [])
    let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: provider,
                                     activeProfile: nil, settings: settings())

    await coord.reactToCheckin(checkin)

    #expect(try ctx.fetch(FetchDescriptor<CoachNoteModel>()).filter { $0.kindRaw == "checkin" }.isEmpty)
}

@Test func checkinReactionSkippedWhenToggledOff() async throws {
    let ctx = ModelContext(try container())
    let checkin = DailyCheckinModel(date: Date())
    checkin.soreness = 9
    ctx.insert(checkin); try ctx.save()
    let provider = StubLLMProvider(responses: [])
    var s = settings(); s.checkinOn = false
    let coord = ProactiveCoordinator(context: ctx, catalog: catalog(), provider: provider,
                                     activeProfile: nil, settings: s)

    await coord.reactToCheckin(checkin)

    #expect(try ctx.fetch(FetchDescriptor<CoachNoteModel>()).filter { $0.kindRaw == "checkin" }.isEmpty)
}
```

- [ ] **Step 2: Implement** — replace the `reactToCheckin(_:)` stub:

```swift
func reactToCheckin(_ checkin: DailyCheckinModel) async {
    guard settings.checkinOn, let provider else { return }
    let sorenessHigh = (checkin.soreness ?? 0) >= 7
    let sleepLow = checkin.sleepQuality.map { $0 <= 3 } ?? false
    guard sorenessHigh || sleepLow else { return }

    let system = ProactivePromptBuilder.system()
    let user = ProactivePromptBuilder.userCheckinReaction(
        soreness: checkin.soreness, sleepQuality: checkin.sleepQuality, note: checkin.note,
        recentSessionsDigest: recentSessionsDigest(limit: 3), memoryDigest: memoryDigest())

    do {
        let result: ToolLoopResult<CheckinReactionDTO> = try await ToolLoopRunner().run(
            system: system, initialUser: user, finalSchema: ProactivePromptBuilder.checkinReactionSchema,
            tools: ToolRegistry(tools: []), provider: provider)
        recordCalls(result.calls, callType: "checkinReaction")
        let text = result.value.message
        context.insert(CoachNoteModel(kindRaw: "checkin", text: text))
        try? context.save()

        // Ping only if the app isn't foreground when the reaction lands.
        if UIApplication.shared.applicationState != .active {
            let content = UNMutableNotificationContent()
            content.title = "From your coach"
            content.body = text
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2 * 3600, repeats: false)
            notificationCenter.removePendingNotificationRequests(withIdentifiers: ["proactive_checkin"])
            notificationCenter.add(UNNotificationRequest(identifier: "proactive_checkin", content: content, trigger: trigger))
        }
    } catch ToolLoopError.exceededMaxIterations(let calls) {
        recordCalls(calls, callType: "checkinReaction")
    } catch { return }
}
```

**Note for the implementer:** `UIApplication.shared.applicationState` needs
`import UIKit`. In a unit test there's no foreground app, so
`applicationState` won't be `.active` — the tests above only assert the
`CoachNoteModel` is written, not the notification, so they pass regardless.
If `UIApplication.shared` is unavailable in the test target and crashes,
guard it with `#if canImport(UIKit)` and treat "can't tell" as "not active".

- [ ] **Step 3: Run tests, then commit**

```bash
git add FitnessTracker/FitnessTracker/AI/ProactiveCoordinator.swift \
        FitnessTracker/FitnessTrackerTests/ProactiveCoordinatorTests.swift
git commit -m "Add check-in reaction to ProactiveCoordinator"
```

---

## Task 7: `CheckinEntryView` + Home entry point

**Files:**
- Create: `Features/Home/CheckinEntryView.swift`
- Modify: `Features/Home/HomeView.swift`

- [ ] **Step 1: Implement `CheckinEntryView.swift`**

A sheet: two `Slider`s (sleep quality 1–10, soreness 1–10, integer steps),
a `TextField` note, a Save button. On Save: find today's `DailyCheckinModel`
(`Calendar.isoUTC.isDate($0.date, inSameDayAs: .now)`) or create one, set
`sleepQuality`/`soreness`/`note`, `try? context.save()`, then call an
`onSaved: (DailyCheckinModel) -> Void` closure the parent passes (which fires
`Task { await proactive.reactToCheckin(checkin) }`), then dismiss.

Match `HomeView`'s existing styling tokens (`GymTheme.*`). Keep it small —
this is a form sheet, not a screen.

- [ ] **Step 2: Wire into `HomeView`**

Add a "Daily check-in" button (a small card or a row in the header area —
match the existing Home layout) that presents `CheckinEntryView` as a
`.sheet`. `HomeView` builds a `ProactiveCoordinator` the same way it builds
other coordinators (it already resolves `catalog`, and can resolve a provider
+ `activeProviderProfile` the way `SessionContainerView` does) to pass into
`onSaved`.

**Note for the implementer:** `HomeView` already has `@Environment(\.modelContext)`
and a `catalog`. For the provider, reuse whatever pattern the file (or its
neighbors) already established after the Ask Coach work — grep `HomeView.swift`
for `LLMProviderFactory` / `activeProviderProfile` first; if it's not there
yet, copy `SessionContainerView`'s `@Query` + `.first { $0.isActive }` +
`try? LLMProviderFactory.make(from:)` shape.

- [ ] **Step 3: Build, full suite, commit**

```bash
git add FitnessTracker/FitnessTracker/Features/Home/CheckinEntryView.swift \
        FitnessTracker/FitnessTracker/Features/Home/HomeView.swift
git commit -m "Add daily check-in entry screen wired to the proactive check-in reaction"
```

---

## Task 8: `WeeklySummaryView` + entry points

**Files:**
- Create: `Features/Stats/WeeklySummaryView.swift`
- Modify: `Features/Home/HomeView.swift`, `RootView.swift`

- [ ] **Step 1: Implement `WeeklySummaryView.swift`**

`@Query(sort: \WeeklySummaryModel.weekStartDate, order: .reverse) private var
summaries: [WeeklySummaryModel]`. Render the most recent one's `headline`
(large), `summaryBody`, and `nextWeekFocus` (labelled), then a few
deterministic rows below it computed inline from `@Query`ed
`CompletedSessionModel`/`PersonalRecordModel` — sessions completed this week,
current streak (`StreakCalculator`), PRs this week. Empty state ("No weekly
recap yet — check back after your week wraps up") when `summaries.isEmpty`.
Match `StatsView`'s styling.

- [ ] **Step 2: Entry points**

- `HomeView`: a "This week" card/button (shown when a `WeeklySummaryModel`
  exists) presenting `WeeklySummaryView` as a `.sheet`.
- `RootView`: register a `UNUserNotificationCenterDelegate` (or use
  `.onOpenURL` / a `@State` flag set from a notification-response handler) so
  tapping the `proactive_weekly` notification (`userInfo["proactive"] ==
  "weekly"`) opens `WeeklySummaryView`. Simplest: a small
  `NotificationResponder: NSObject, UNUserNotificationCenterDelegate` class
  set as `UNUserNotificationCenter.current().delegate` in `RootView.task`,
  publishing a `@Published`/`@Observable` flag `RootView` observes to present
  the sheet. If wiring the delegate cleanly proves fiddly, a Home entry point
  alone is acceptable for this task — note the deferral in the report.

- [ ] **Step 3: Build, full suite, commit**

```bash
git add FitnessTracker/FitnessTracker/Features/Stats/WeeklySummaryView.swift \
        FitnessTracker/FitnessTracker/Features/Home/HomeView.swift \
        FitnessTracker/FitnessTracker/RootView.swift
git commit -m "Add weekly summary screen with Home and notification-tap entry points"
```

---

## Task 9: `CoachNoteCard` + Home wiring

**Files:**
- Create: `Features/Home/CoachNoteCard.swift`
- Modify: `Features/Home/HomeView.swift`

- [ ] **Step 1: Implement `CoachNoteCard.swift`**

Follows `PendingObservationCard.swift`/`SuggestionCard.swift` exactly (same
`GymTheme` tokens, same shape). Content: a small kind label ("Coach",
optionally the kind: daily/weekly/check-in/pattern), the `text`, and a single
"Got it" button. `onDismiss` sets `readAt = .now` and saves.

- [ ] **Step 2: Wire into `HomeView`**

```swift
@Query(sort: \CoachNoteModel.createdAt, order: .reverse) private var allCoachNotes: [CoachNoteModel]
private var unreadCoachNotes: [CoachNoteModel] { allCoachNotes.filter { $0.readAt == nil } }
```

Render `ForEach(unreadCoachNotes)` as `CoachNoteCard`s in the same Home
section as the pending-observation / suggestion cards (above or below them —
your call, keep it visually coherent). `onDismiss` → `note.readAt = .now; try?
context.save()`.

- [ ] **Step 3: Build, full suite, commit**

```bash
git add FitnessTracker/FitnessTracker/Features/Home/CoachNoteCard.swift \
        FitnessTracker/FitnessTracker/Features/Home/HomeView.swift
git commit -m "Add CoachNoteCard: Home surface for proactive coach messages"
```

---

## Task 10: Settings toggles + per-identifier notification cleanup

**Files:**
- Modify: `Features/Settings/SettingsView.swift`

- [ ] **Step 1: Add per-type toggles**

In `notificationsSection`, under the existing "Workout day reminder" toggle,
add (visible only when the master permission path is active — i.e. gate on
the same `reminderOn` or on a fresh `@AppStorage("notif_permission_granted")`
if you add one):

```swift
Toggle("Daily coach heads-up", isOn: $proactiveDailyOn).tint(activeAccent)
Toggle("Weekly recap", isOn: $proactiveWeeklyOn).tint(activeAccent)
Toggle("InBody scan reminder", isOn: $proactiveInBodyOn).tint(activeAccent)
Toggle("Soreness / sleep check-in reactions", isOn: $proactiveCheckinOn).tint(activeAccent)
Toggle("Training pattern nudges", isOn: $proactivePatternOn).tint(activeAccent)
```

Backed by `@AppStorage` keys: `proactive.settings.daily`, `.weekly`,
`.inbody`, `.checkin`, `.pattern` — all defaulting `true`. These are the keys
`RootView`/`HomeView` read to build `ProactiveSettings`.

- [ ] **Step 2: Stop `scheduleWorkoutReminder` from nuking proactive notifications**

Change `scheduleWorkoutReminder`'s
`UNUserNotificationCenter.current().removeAllPendingNotificationRequests()`
to `removePendingNotificationRequests(withIdentifiers: ["gym_daily_reminder"])`,
and the disable branch of the "Workout day reminder" toggle's `onChange`
likewise (it currently also calls `removeAllPendingNotificationRequests()`).
Proactive notifications own the `proactive_*` identifiers and must survive an
unrelated workout-reminder toggle.

- [ ] **Step 3: Build, full suite, commit**

```bash
git add FitnessTracker/FitnessTracker/Features/Settings/SettingsView.swift
git commit -m "Add proactive-notification Settings toggles; scope reminder cleanup to its own identifier"
```

---

## Task 11: Run `ProactiveCoordinator` on app foreground

**Files:**
- Modify: `RootView.swift`

- [ ] **Step 1: Wire scenePhase**

Add `@Environment(\.scenePhase) private var scenePhase` and the five
`@AppStorage("proactive.settings.*")` bindings to `RootView`. Add:

```swift
.onChange(of: scenePhase) { _, phase in
    guard phase == .active, let catalog else { return }
    runProactive(catalog: catalog)
}
```

and call `runProactive` once from the existing `.task` block too (after
`catalog` is loaded). `runProactive` builds `ProactiveSettings` from the
`@AppStorage` values + the existing `reminderHour`/`reminderMinute`, resolves
a provider the same way `regeneratePlan` already resolves `activeProfiles.first`
(and `try? LLMProviderFactory.make(from:)`), constructs `ProactiveCoordinator`,
and fires `Task { await coordinator.runDueChecks() }`. Fire-and-forget — it
must not block or be `await`ed inline.

- [ ] **Step 2: Build, full test suite (final verification pass), commit**

```bash
git add FitnessTracker/FitnessTracker/RootView.swift
git commit -m "Run ProactiveCoordinator.runDueChecks on app foreground"
```

---

## Self-Review Notes

- **Placeholder scan**: every task has real code. The "Note for the
  implementer" flags mark genuine signature-verification points (RecoveryModel,
  StreakCalculator, MuscleBalanceModel, UIApplication-in-tests, HomeView's
  provider pattern) that this plan can't fully resolve without the files open
  — the same technique every prior plan in this project used.
- **The `body` field name**: `WeeklySummaryModel.summaryBody` (not `body`) is
  deliberate — flagged in Task 1 — to avoid the SwiftUI `body` collision in
  `WeeklySummaryView`.
- **`removeAllPendingNotificationRequests` is a landmine**: Task 10 Step 2
  fixes the pre-existing call so this whole feature isn't silently wiped every
  time the user toggles the unrelated workout reminder. If a reviewer sees a
  proactive notification "not persisting," this is the first suspect.
- **Scope**: all five §7 triggers + the check-in and weekly screens. Rich
  notification actions, server push, and in-app per-notification snooze are
  explicit non-goals (spec §8).

## Execution

Subagent-driven (`superpowers:subagent-driven-development`). 11 tasks; Tasks
3–6 all modify `ProactiveCoordinator.swift` sequentially, so they must run in
order, not batched.
