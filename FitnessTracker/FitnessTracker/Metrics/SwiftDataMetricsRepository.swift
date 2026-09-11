import Foundation
import SwiftData
import Metrics
import FitnessDomain
import ExerciseCatalog

/// SwiftData-backed `MetricsRepository`.
///
/// Thin fetch-and-forward adapter: it fetches the relevant rows once per
/// repository lifetime, maps them to the Phase 2a snapshot value types, and delegates to
/// `InMemoryMetricsRepository` — the pure implementation of every metric
/// algorithm. This type re-implements none of that logic.
///
/// The snapshot is immutable for the lifetime of this short-lived repository.
/// Session finalization creates one repository per session start, so caching
/// avoids rebuilding the complete workout-history graph for every exercise
/// while preserving fresh data for each new operation.
///
/// Isolation: the struct is `@MainActor` because it touches `ModelContext`.
/// `MetricsRepository` no longer refines `Sendable` (the AI coach orchestrator
/// needs to call it around an `await` and get a compile-time guarantee it's on
/// the main actor, not a runtime trap), so these are ordinary `@MainActor`
/// methods — no `nonisolated`/`MainActor.assumeIsolated` dance needed.
@MainActor
private final class SwiftDataMetricsSnapshotCache {
    var repository: InMemoryMetricsRepository?
    var buildCount = 0
}

@MainActor
struct SwiftDataMetricsRepository: MetricsRepository {
    private let context: ModelContext
    private let catalog: CatalogStore
    private let plannedSessionsPerWeek: Int
    private let calendar: Calendar
    private let snapshotCache: SwiftDataMetricsSnapshotCache

    init(context: ModelContext,
         catalog: CatalogStore,
         plannedSessionsPerWeek: Int,
         now: @escaping () -> Date = { .now },
         calendar: Calendar = .appWeek) {
        self.context = context
        self.catalog = catalog
        self.plannedSessionsPerWeek = plannedSessionsPerWeek
        self.calendar = calendar
        self.snapshotCache = SwiftDataMetricsSnapshotCache()
        // `now` is part of the documented init shape. The protocol's windowed
        // methods (`weeklyVolume`, `adherence`) receive `now:` as a parameter, so
        // nothing in this adapter needs the closure.
        _ = now
    }

    // MARK: - Inner pure repository

    /// Fetches every *finished* session (`finishedAt != nil`), maps to snapshots,
    /// and constructs an `InMemoryMetricsRepository` over them. A session start
    /// asks for the last performance of several exercises; reuse the same
    /// immutable snapshot for that operation instead of refetching the entire
    /// history once per exercise on the main actor.
    private func inner() -> InMemoryMetricsRepository {
        if let repository = snapshotCache.repository {
            return repository
        }
        let finished = ((try? context.fetch(FetchDescriptor<CompletedSessionModel>())) ?? [])
            .filter { $0.finishedAt != nil }
            .map { $0.toSnapshot() }
        let repository = InMemoryMetricsRepository(
            sessions: finished,
            priorPRs: [],
            observations: [],
            plannedSessionsPerWeek: plannedSessionsPerWeek,
            catalog: catalog,
            calendar: calendar)
        snapshotCache.repository = repository
        snapshotCache.buildCount += 1
        return repository
    }

    /// Internal visibility keeps the cache behavior regression-tested without
    /// exposing implementation details to app callers.
    var snapshotBuildCount: Int { snapshotCache.buildCount }

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
        guard weeks > 0,
              let windowStart = calendar.date(byAdding: .day, value: -weeks * 7, to: now) else { return 0 }
        let finished = ((try? context.fetch(FetchDescriptor<CompletedSessionModel>())) ?? [])
            .filter { $0.finishedAt != nil }
        let completed = finished.filter { $0.startedAt >= windowStart && $0.startedAt <= now }.count
        var planned = 0
        for offset in 0..<weeks {
            guard let start = calendar.date(byAdding: .day, value: offset * 7, to: windowStart),
                  let end = calendar.date(byAdding: .day, value: 7, to: start) else { continue }
            let slots = WorkoutScheduleStore.plannedSlotCount(in: DateInterval(start: start, end: end))
            planned += slots > 0 ? slots : plannedSessionsPerWeek
        }
        guard planned > 0 else { return 0 }
        return min(1, max(0, Double(completed) / Double(planned)))
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
            .filter { $0.confirmed }
            .map { $0.toSnapshot() }
            .filter { o in o.kind == kind && (since.map { o.timestamp >= $0 } ?? true) }
    }
}
