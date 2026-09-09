# Unified automatic missed-session scheduling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task by task.

**Goal:** Make missed-session catch-up a single, persisted scheduling rule used consistently by every app surface and data/AI consumer, not only HomeView.

**Architecture:** Keep the pure Monday–Sunday rescheduling algorithm in `FitnessCore/Scheduling`. Add one app-layer `WorkoutScheduleStore` that owns the recurring weekday template, date overrides, completion reconciliation, and conversion between the app's Monday-first indices and Core's Calendar weekday keys. Views, session launch, proactive AI, memory, exports, and metrics read this store instead of deriving schedule state independently.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, `@AppStorage`/`UserDefaults`, FitnessCore package tests, Xcode simulator.

**Spec:** `docs/plans/2026-09-03-phase-3e-notes-scheduling.md` and `docs/plans/2026-09-04-ui-parity-gap-doc.md`.

**Global constraints:** Preserve explicit date overrides; Sunday remains excluded from automatic catch-up; use focused tests/builds only; do not alter unrelated worktree changes; do not add an external backend.

## Task 1: Establish the shared schedule state and tests

Create an app-layer schedule value/store with Codable persistence for `gym_week_schedule_json` and `gym_day_plan_json`, helpers for effective routine, source/target reschedule metadata, current-week slots, and mapping to `WeeklyPlan` sessions. Add tests for mapping, idempotence, explicit overrides, and completed dates.

## Task 2: Route all workout-facing UI through the store

Replace HomeView's duplicated parsing and scheduling logic. Wire RootView's Start action, WorkoutTabView's today session, PlanView's template/override state, DayOverrideSheet persistence, and CalendarSheet's planned/rest/rescheduled indicators to the shared store. Ensure date overrides survive template edits and manual choices are not overwritten by reconciliation.

## Task 3: Route proactive coach, tools, memory, and exports through schedule context

Make proactive daily/weekly generation use the effective current/next session and label catch-up work. Include dated/rescheduled upcoming sessions in suggestion tools and prompt context. Pass the effective schedule into memory capture. Export recurring schedule, date overrides, and effective week metadata alongside workout history.

## Task 4: Make metrics and summaries schedule-aware

Use effective scheduled slots for current-week planned counts and adherence/weekly summaries where those values are derived. Keep a backwards-compatible fallback to the profile's sessions-per-week value when no schedule is available.

## Task 5: Verify the integrated behavior

Run the focused Core scheduling tests, app schedule tests, targeted Xcode tests/build, and a simulator smoke check covering a missed weekday, catch-up assignment, Home/Plan/Workout consistency, and proactive/export schedule context. Inspect the rendered simulator screen after UI changes.
