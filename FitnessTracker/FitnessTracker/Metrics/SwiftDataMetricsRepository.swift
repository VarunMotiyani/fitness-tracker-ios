import Foundation
import SwiftData
import Metrics
import FitnessDomain
import ExerciseCatalog

/// SwiftData-backed `MetricsRepository`.
///
/// Thin fetch-and-forward adapter: on every call it fetches the relevant rows,
/// maps them to the Phase 2a snapshot value types, and delegates to
/// `InMemoryMetricsRepository` — the pure implementation of every metric
/// algorithm. This type re-implements none of that logic.
///
/// `inner()` is rebuilt on every call — no memoisation. At personal-log scale
/// that is cheap, and it guarantees each query observes the current
/// `ModelContext` state (plan pre-flight Ruling 3: a caching layer is a
/// documented deferral).
///
/// Isolation: the struct is `@MainActor` because it touches `ModelContext`.
/// `MetricsRepository` no longer refines `Sendable` (the AI coach orchestrator
/// needs to call it around an `await` and get a compile-time guarantee it's on
/// the main actor, not a runtime trap), so these are ordinary `@MainActor`
/// methods — no `nonisolated`/`MainActor.assumeIsolated` dance needed.
@MainActor
struct SwiftDataMetricsRepository: MetricsRepository {
    private let context: ModelContext
    private let catalog: CatalogStore
    private let plannedSessionsPerWeek: Int
    private let calendar: Calendar

    init(context: ModelContext,
         catalog: CatalogStore,
         plannedSessionsPerWeek: Int,
         now: @escaping () -> Date = { .now },
         calendar: Calendar = .isoUTC) {
        self.context = context
        self.catalog = catalog
        self.plannedSessionsPerWeek = plannedSessionsPerWeek
        self.calendar = calendar
        // `now` is part of the documented init shape. The protocol's windowed
        // methods (`weeklyVolume`, `adherence`) receive `now:` as a parameter, so
        // nothing in this adapter needs the closure.
        _ = now
    }

    // MARK: - Inner pure repository

    /// Fetches every *finished* session (`finishedAt != nil`), maps to snapshots,
    /// and constructs a fresh `InMemoryMetricsRepository` over them.
    private func inner() -> InMemoryMetricsRepository {
        let finished = ((try? context.fetch(FetchDescriptor<CompletedSessionModel>())) ?? [])
            .filter { $0.finishedAt != nil }
            .map { $0.toSnapshot() }
        return InMemoryMetricsRepository(
            sessions: finished,
            priorPRs: [],
            observations: [],
            plannedSessionsPerWeek: plannedSessionsPerWeek,
            catalog: catalog,
            calendar: calendar)
    }

    // MARK: - Forwarded straight to the pure repository

    func lastPerformance(exerciseID: String) -> ExercisePerformance? {
        inner().lastPerformance(exerciseID: exerciseID)
    }

    func bestSet(exerciseID: String, since: Date?) -> LoggedSetSnapshot? {
        inner().bestSet(exerciseID: exerciseID, since: since)
    }

    func e1RMSeries(exerciseID: String, since: Date?) -> [ExerciseTrendPoint] {
        inner().e1RMSeries(exerciseID: exerciseID, since: since)
    }

    func weeklyVolume(muscle: MuscleGroup, weeks: Int, now: Date) -> [WeeklyMuscleVolume] {
        inner().weeklyVolume(muscle: muscle, weeks: weeks, now: now)
    }

    func adherence(weeks: Int, now: Date) -> Double {
        inner().adherence(weeks: weeks, now: now)
    }

    func stalls() -> [String] {
        inner().stalls()
    }

    // MARK: - Backed directly by their own tables

    /// The authoritative PRs the runner persists at session-finish. Not derived
    /// via `inner()` — re-deriving would double-count.
    func personalRecords(exerciseID: String?) -> [PersonalRecord] {
        let snapshots = ((try? context.fetch(FetchDescriptor<PersonalRecordModel>())) ?? [])
            .map { $0.toSnapshot() }
        guard let exerciseID else { return snapshots }
        return snapshots.filter { $0.exerciseID == exerciseID }
    }

    func observations(kind: String, since: Date?) -> [ObservationSnapshot] {
        ((try? context.fetch(FetchDescriptor<ObservationModel>())) ?? [])
            .map { $0.toSnapshot() }
            .filter { o in o.kind == kind && (since.map { o.timestamp >= $0 } ?? true) }
    }
}
