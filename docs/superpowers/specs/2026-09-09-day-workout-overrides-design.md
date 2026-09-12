# Date-Scoped Workout Editing Design

## Goal

Let an athlete tailor the exercises in a scheduled workout for one calendar date without changing the recurring routine. The effective one-day workout must be the version shown by Home and Start, used when logging the session, exported to the coach context, and available to future AI features.

## Scope and non-goals

- This feature edits a single scheduled date only. It never changes the weekly routine, its recurring weekdays, or another date.
- A Push day remains a Push day. Exercise candidates must match at least one focus muscle of the scheduled session; the user cannot swap the day into Pull or Legs.
- The existing date-level routine override and automatic catch-up scheduler remain responsible for which session is scheduled. This feature only overrides the exercises inside that effective session.
- Editing targets (sets, reps, load, rest) is deferred. The initial release supports add, replace, and remove while retaining the original prescription for unchanged exercises. An added exercise starts at 3 sets of 8–12 reps, no prescribed load, and 90 seconds rest.

## Data contract

`WorkoutScheduleStore` owns a second, independently persisted JSON value keyed by ISO calendar date:

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
```

- The override stores the full effective item list, not a fragile list of patch operations.
- `baseSessionID` prevents an override from silently applying to a regenerated, unrelated routine. If the scheduled session for the date no longer has that ID, the override is ignored; it remains removable from the store but is not used to start a workout.
- `effectiveSession(for:in:)` first resolves the existing schedule/routine selection, then applies a valid same-date workout override by creating a `PlannedSession` with the original ID, order, and focus muscles but overridden items.
- `saveDayWorkoutOverride`, `removeDayWorkoutOverride`, and focused helpers for replace/add/remove are the only mutation API. All UI and future AI code use those APIs.
- `origin` is exported with the date and item list so AI prompts can distinguish a manual one-day change from the original weekly plan. The current UI only writes `.manual`; the public contract leaves an intentional, tested path for `.ai`.

## User flow

### Day sheet

1. Tapping a scheduled date opens its day sheet as today.
2. Tapping the planned-workout card expands a compact "Today’s Push Day" editor directly beneath it. It lists every effective exercise using the existing thumbnail/image component, name, and prescription.
3. Tapping an exercise opens its detailed exercise page. In this context that page gains date-scoped actions: **Replace exercise** and **Remove from today**. Neither action edits the recurring plan.
4. **Add exercise** appears after the list. It navigates to the actual Exercises tab in a scoped selection state.
5. **Change workout** remains a green disclosure directly attached to its revealed, Push-compatible choices. The recovery action never interrupts this visual group.
6. **Rest today** becomes a compact, low-emphasis recovery action at the bottom of the day sheet. Choosing it asks for confirmation before creating the existing `"rest"` date override.
7. When a workout override exists, the sheet identifies it as "Custom for today" and offers **Reset today’s workout**. Reset deletes only the exercise override; the regular scheduled Push session reappears.

### Exercises tab handoff

`RootView` holds a transient `ExerciseLibraryIntent` containing the date, base session ID, session focus muscles, and action (`add` or `replace(existingExerciseID:)`). Setting the intent selects the Exercises tab.

`LibraryView` continues to behave normally when no intent exists. With an intent it:

- shows a persistent context header: "Editing today’s Push Day";
- limits candidates to exercises whose primary or secondary muscles intersect the session focus muscles;
- opens the normal exercise detail page when an exercise is tapped;
- shows the date-scoped primary action in that detail page: **Add to today’s workout** or **Replace [exercise]**;
- persists via `WorkoutScheduleStore`, clears the intent, and returns to the date sheet/editor so the athlete sees the updated list.

The detail page remains a place to understand an exercise before committing. A selection is never persisted merely by opening a row.

## Consumer and AI consistency

Every read that currently calls `WorkoutScheduleStore.plannedSession(for:in:)` is moved to `effectiveSession(for:in:)` where it represents a scheduled day: Home’s today card and day sheet, the Start tab, the center Start action, proactive scheduling, and AI schedule/context construction. Code that intentionally needs the recurring plan continues to read `plan.sessions` directly.

Completed-session history already records the chosen exercise entries. The JSON history export additionally includes each active date-level workout override, origin, base session ID, and planned items. This makes the current manual intent visible to `QueryTrainingDataTool` and all prompts that consume the exported training data.

## UX and accessibility rules

- Every tap target is at least 44 by 44 points and has a meaningful VoiceOver label and hint.
- Exercise thumbnails are decorative when the row label already names the exercise.
- The expanded change-workout panel and its trigger share a single visual container and adjacent position; no unrelated action sits between them.
- Rest is visually subordinate, confirmation-protected, and never styled as the primary action.
- Loading/save feedback confirms an add, replace, remove, or reset before the navigation handoff completes.
- The existing dark GymTheme and semantic accent token remain the visual source of truth; no raw per-screen colors are added.

## Failure handling

- If there is no scheduled session, exercise editing is unavailable; the sheet offers only adding a scheduled routine via the existing date override flow.
- If the stored override belongs to a stale base session, it is ignored and the unchanged scheduled session is used. The UI presents a reset action rather than applying stale exercises to a regenerated plan.
- Empty overrides are not stored: removing the final item restores the original scheduled session after confirmation, rather than producing an unstartable workout.
- A replacement is rejected if its focus muscles do not intersect the base session’s focus muscles or if it would duplicate another selected exercise.

## Verification

- Unit tests cover effective-session resolution, isolation from the weekly plan, replacement, addition, removal, reset, stale-base rejection, duplicate prevention, and exported manual override data.
- Focused UI tests/logic tests cover the day-sheet state ordering: planned card → attached change panel; rest action remains outside that group; editing intent filters to matching muscle groups.
- A targeted build runs against the existing shared simulator only. The updated app is installed/launched in that existing window for visual inspection; no simulator is created, booted, reset, or closed.
