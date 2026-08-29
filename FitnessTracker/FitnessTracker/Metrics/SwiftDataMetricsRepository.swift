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
/// `MetricsRepository` refines `Sendable`, so the conformance cannot itself be
/// main-actor-isolated (`SendableMetatype` rejects that), and a `@MainActor`
/// method cannot satisfy a `nonisolated` requirement. Each protocol method is
/// therefore declared `nonisolated` with its body in `MainActor.assumeIsolated`
/// — safe because every call site in the app is `@MainActor`. The struct is not
/// made `nonisolated`.
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
    // safe: all call sites are @MainActor

    nonisolated func lastPerformance(exerciseID: String) -> ExercisePerformance? {
        MainActor.assumeIsolated { inner().lastPerformance(exerciseID: exerciseID) }
    }

    nonisolated func bestSet(exerciseID: String, since: Date?) -> LoggedSetSnapshot? {
        MainActor.assumeIsolated { inner().bestSet(exerciseID: exerciseID, since: since) }
    }

    nonisolated func e1RMSeries(exerciseID: String, since: Date?) -> [ExerciseTrendPoint] {
        MainActor.assumeIsolated { inner().e1RMSeries(exerciseID: exerciseID, since: since) }
    }

    nonisolated func weeklyVolume(muscle: MuscleGroup, weeks: Int, now: Date) -> [WeeklyMuscleVolume] {
        MainActor.assumeIsolated { inner().weeklyVolume(muscle: muscle, weeks: weeks, now: now) }
    }

    nonisolated func adherence(weeks: Int, now: Date) -> Double {
        MainActor.assumeIsolated { inner().adherence(weeks: weeks, now: now) }
    }

    nonisolated func stalls() -> [String] {
        MainActor.assumeIsolated { inner().stalls() }
    }

    // MARK: - Backed directly by their own tables
    // safe: all call sites are @MainActor

    /// The authoritative PRs the runner persists at session-finish. Not derived
    /// via `inner()` — re-deriving would double-count.
    nonisolated func personalRecords(exerciseID: String?) -> [PersonalRecord] {
        MainActor.assumeIsolated {
            let snapshots = ((try? context.fetch(FetchDescriptor<PersonalRecordModel>())) ?? [])
                .map { $0.toSnapshot() }
            guard let exerciseID else { return snapshots }
            return snapshots.filter { $0.exerciseID == exerciseID }
        }
    }

    nonisolated func observations(kind: String, since: Date?) -> [ObservationSnapshot] {
        MainActor.assumeIsolated {
            ((try? context.fetch(FetchDescriptor<ObservationModel>())) ?? [])
                .map { $0.toSnapshot() }
                .filter { o in o.kind == kind && (since.map { o.timestamp >= $0 } ?? true) }
        }
    }
}
