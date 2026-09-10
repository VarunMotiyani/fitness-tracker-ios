# Persistence Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make every user-owned value survive app close reliably, prevent duplicate/phantom data, and make backup/reset behavior truthful.

**Architecture:** Keep SwiftData as the source of truth for relational app data, UserDefaults for preferences/schedule snapshots, and Keychain for secrets. Add guarded, throwing persistence boundaries and deterministic import/export helpers; do not introduce a hosted backend.

**Tech Stack:** SwiftUI, SwiftData, UserDefaults/@AppStorage, Security Keychain, Swift Testing.

**Spec:** Persistence audit findings from the current app review.

## Global Constraints

- Do not open or close simulator windows; use the existing device/build flow only.
- Preserve current uncommitted signing/app-icon changes.
- No production write without a failing regression test first.
- Keep user data local to the iPhone.

### Task 1: Safe SwiftData save boundary

**Files:** Create `FitnessTracker/FitnessTracker/Persistence/PersistenceError.swift`; modify user-facing save call sites; test `FitnessTracker/FitnessTrackerTests/PersistenceErrorTests.swift`.

- [ ] Add a small error-reporting helper and replace silent saves in user-facing flows first.
- [ ] Add tests proving save errors are returned rather than swallowed.
- [ ] Convert provider/profile, check-in, weight, plan, import, reset, and session-critical saves to explicit `do/catch` paths.

### Task 2: Guarded demo seeding and startup scheduling

**Files:** Modify `RootView.swift`, `HomeView.swift`, `LogWeightSheet.swift`, `WorkoutScheduleStore.swift`; test `PersistenceStartupTests.swift`.

- [ ] Test that existing rows never trigger demo seeding and that scheduling waits for authoritative fetches.
- [ ] Use direct fetches/one-time seed markers rather than transient `@Query.isEmpty` checks.
- [ ] Recompute automatic rescheduling only after completed sessions are loaded.

### Task 3: Idempotent imports

**Files:** Modify `HistoryIngestionService.swift`, `HevyAPIClient.swift`; test `HistoryIngestionServiceTests.swift`.

- [ ] Test importing the same external session twice leaves one stored session.
- [ ] Preserve stable external IDs where available and upsert by stable ID/date/source fallback.
- [ ] Return/propagate save failures instead of reporting success.

### Task 4: Real complete backup and restore

**Files:** Modify `HistoryExportManager.swift`, `SettingsView.swift`; create `BackupRestoreService.swift`; test `HistoryExportManagerTests.swift`.

- [ ] Test round-tripping profile, plans, history, chat, coach memory/notes, preferences, and schedule layers.
- [ ] Export all user-owned data while excluding secrets.
- [ ] Restore into SwiftData/UserDefaults transactionally enough to avoid false success.

### Task 5: Complete reset and secret storage

**Files:** Modify `SettingsView.swift`, `HevyAPISyncSheet.swift`, `KeychainStore.swift`; test reset/keychain behavior.

- [ ] Test reset clears every user-data model and owned preference key while retaining no credentials.
- [ ] Move Hevy API key from UserDefaults to Keychain.
- [ ] Make the reset confirmation match the actual scope.

### Task 6: Onboarding durability and disk-backed verification

**Files:** Modify `RootView.swift`; create/modify persistence tests.

- [ ] Test that the profile is saved before asynchronous plan generation.
- [ ] Add a disk-backed ModelContainer reopen test for profile/bodyweight/session data.
- [ ] Run build-for-testing and existing unit tests; report any device-signing limitation separately.
