# Proactive Notifications & Coach Outreach — Design

## 1. Goal

Build the proactive layer from `docs/specs/2026-09-05-ai-coach-layer-v2-design.md`
§7 — the coach reaching out on its own, not just answering. All five
LLM/notification triggers (#6 daily, #7 weekly, #8 InBody, #9 check-in
reaction, #10 pattern nudge), plus the two UI surfaces they need that don't
exist yet: a daily check-in entry screen and a weekly summary screen.

## 2. The hard constraint that shapes everything

An iOS local notification fires while the app is backgrounded or killed. It
**cannot run an LLM call at fire time.** So every LLM-backed notification's
text must be generated while the app is *foregrounded* and scheduled ahead of
time with that text baked into the `UNNotificationRequest` body. The design
doc's §7 ("one short LLM call" per daily notification) glossed over this;
the real mechanism is: generate-when-open, schedule-pre-baked.

## 3. `ProactiveCoordinator`

`@MainActor struct ProactiveCoordinator` — one entry point, run from
`RootView` whenever the app becomes active (`@Environment(\.scenePhase)` +
`.onChange(of: scenePhase)` firing when it flips to `.active`, plus once on
first `.task`). Holds `ModelContext`, `catalog`, `provider: (any LLMProvider)?`,
`activeProfile: ProviderProfile?`.

`func runDueChecks() async` does a cheap "what's due?" pass and then, for each
due item, one background LLM call → schedule/persist. Nothing runs if the
matching Settings toggle is off. No provider → the deterministic parts
(InBody reminder) still run; the LLM-backed parts silently skip. Every LLM
call writes one `AICallRecord` (call types: `dailyNarration`,
`weeklySummary`, `checkinReaction`, `patternNudge`), same call-granular
pattern as every other coordinator in this codebase.

**Due-check bookkeeping** uses `@AppStorage`-style `UserDefaults` keys (no new
model needed for scheduling state):
- `proactive.daily.lastGeneratedDay` — a `yyyy-MM-dd` string. Due if != today.
- `proactive.weekly.lastWeekStart` — an ISO date string. Due if the current
  ISO week's start differs.
- Pattern-nudge dedup: `proactive.patternNudge.<memoryUUID>` = last-nudged
  ISO date. Due if absent or > 14 days ago.
- InBody: a single repeating `UNTimeIntervalNotificationTrigger`, reset
  (removed + re-added) when a `bodyFatPercent`/`muscleMassKg` `ObservationModel`
  becomes `confirmed`.

## 4. The five triggers

### #6 Daily narration
When due, one LLM call: inputs = today's (or, if today's session is done,
tomorrow's) `PlannedSession` from the current `StoredPlan`, a recovery-status
digest (`RecoveryModel.computeRecovery`), and `MemoryRecall.select(…).digest`.
Output DTO `{ narration: String }` — one or two sentences ("Today's push day —
your triceps are freshest, lead with dips"). Schedule a
`UNCalendarNotificationTrigger` at the user's existing reminder hour
(`repeats: false`, identifier `proactive_daily`), body = the narration. Also
write a `CoachNoteModel(kind: "daily", text: narration)` so it shows on Home
even if notifications are off / already dismissed.

### #7 Weekly summary
When due (new ISO week, not yet generated), one LLM call: inputs = the prior
week's `CompletedSessionModel`s, muscle coverage (`MuscleBalanceModel`),
current streak (`StreakCalculator`), PRs earned that week, memory digest.
Output DTO `{ headline: String, body: String, nextWeekFocus: String }`.
Persist a `WeeklySummaryModel(weekStartDate:, headline:, body:, nextWeekFocus:,
generatedAt:)` (one row per week — replace if regenerated). Schedule a
notification (`proactive_weekly`) whose body is `headline`, tapping through
to `WeeklySummaryView`. Also a `CoachNoteModel(kind: "weekly", …)` for Home.

### #8 InBody reminder
Pure `UNTimeIntervalNotificationTrigger(timeInterval: 5 weeks, repeats:
true)`, identifier `proactive_inbody`, static body ("Time for an InBody scan —
tell your coach the numbers in chat"). No LLM, no model. Registered/cleared
by the Settings toggle; the interval resets when a body-composition
`ObservationModel` is confirmed (so the reminder tracks "5 weeks since your
last real measurement," approximately).

### #9 Check-in reaction
Requires the new **check-in entry screen** (below). On a `DailyCheckinModel`
save where `soreness >= 7` OR `sleepQuality <= 3` (either present and past
threshold), `ProactiveCoordinator.reactToCheckin(_ checkin:)` fires one LLM
call: inputs = the check-in, the last ~3 sessions, memory digest. Output
`{ message: String }`. Write a `CoachNoteModel(kind: "checkin", …)` (shows on
Home immediately). Additionally schedule a one-shot notification (fires ~2h
later, identifier `proactive_checkin`) *only if* the app isn't currently in
the foreground when the reaction completes — so an in-app user sees the card,
a user who logged and closed the app gets pinged.

### #10 Pattern nudge
On `runDueChecks`, fetch `CoachMemoryModel` where `kindRaw ==
"responsePattern"`, `confidence >= 0.6`, not retired, and not nudged in 14
days. For each (cap 1 per run), one LLM call: inputs = the pattern statement,
the last ~5 sessions, memory digest. Output `{ nudge: String }`. Write
`CoachNoteModel(kind: "pattern", …)`. Record the nudge timestamp in
`UserDefaults` per the §3 key.

## 5. New models

- **`CoachNoteModel`** `@Model`: `id: UUID`, `kindRaw: String`
  (`daily`/`weekly`/`checkin`/`pattern`), `text: String`, `createdAt: Date`,
  `readAt: Date?`. Home shows unread ones as cards (same visual language as
  `PendingObservationCard`/`SuggestionCard`); tapping "Got it" sets `readAt`.
- **`WeeklySummaryModel`** `@Model`: `weekStartDate: Date`, `headline: String`,
  `body: String`, `nextWeekFocus: String`, `generatedAt: Date`.

Both purely additive to the `.modelContainer(for:)` list — SwiftData
lightweight migration handles them, consistent with every prior model this
project has added.

## 6. New UI

- **`CheckinEntryView`** — sleep-quality slider (1–10), soreness slider
  (1–10), optional note field, Save. Opened from a Home entry point (a small
  "Daily check-in" button/card). On Save: insert a `DailyCheckinModel` (one
  per calendar day — overwrite today's if it exists), `try? context.save()`,
  then `Task { await proactive.reactToCheckin(checkin) }`.
- **`WeeklySummaryView`** — renders the current `WeeklySummaryModel` (headline,
  body, next-week focus) above a few deterministic stat rows (sessions
  completed, muscle-coverage bars, streak, PRs this week). Reachable from the
  weekly notification and a Home entry point.
- **`CoachNoteCard`** — the Home card for an unread `CoachNoteModel` (kind
  label + text + "Got it"), rendered in the same Home section as the existing
  pending-observation / suggestion cards.
- **Settings** — extend the existing notifications section: master permission
  (exists) plus per-type toggles (daily narration, weekly summary, InBody,
  check-in reactions, pattern nudges), all defaulting on once permission is
  granted; the existing morning-hour picker now also drives the daily
  narration time.

## 7. Failure / edge handling

- No provider configured → InBody reminder still schedules; all LLM-backed
  items skip silently (no `CoachNoteModel`, no notification, no
  `AICallRecord`).
- LLM call throws / decode fails → that one item is skipped this run, retried
  next foreground. Never blocks app launch (all calls are background `Task`s).
- Notification permission denied → nothing schedules; `CoachNoteModel`s still
  appear in-app (the coach still "reaches out," just on the Home screen only).
- Re-running `runDueChecks` multiple times a day is safe — the `UserDefaults`
  day/week keys make every LLM-backed item idempotent per period.

## 8. Non-goals

- Rich notification actions (buttons on the notification itself).
- Server push / background fetch — everything is local, generated while the
  app is open.
- Editing/snoozing individual notifications from within the app beyond the
  Settings on/off toggles.
