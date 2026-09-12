import Foundation
import SwiftData
import Metrics

/// Memoises the `CompletedSessionModel -> CompletedSessionSnapshot` mapping.
/// `HomeView` and `StatsView` derive several analytics off `sessionSnapshots`,
/// each a computed property re-evaluated on every body pass. Building the
/// snapshot trees (which fault the entries/sets relationship graph out of
/// SQLite) every time was a primary on-device hitch.
///
/// The fingerprint touches only scalar columns already loaded on the session
/// row — it must NOT walk `entries`/`sets`, because that fault is exactly the
/// cost being cached. A set/rep edit to an already-finished session from the
/// History screen won't bust the cache on its own; it refreshes on the next
/// `@Query` delivery or app relaunch. Finalizing, deleting, or adding a session
/// all change these scalars and do bust it.
@MainActor
final class SessionSnapshotCache {
    private var fingerprint: Int?
    private var cached: [CompletedSessionSnapshot] = []
    /// Bumped only when `cached` is actually rebuilt — downstream analytics
    /// caches key on this instead of re-diffing the snapshot array.
    private(set) var generation = 0

    func snapshots(from sessions: [CompletedSessionModel]) -> [CompletedSessionSnapshot] {
        var hasher = Hasher()
        var finishedCount = 0
        for session in sessions where session.finishedAt != nil {
            finishedCount += 1
            hasher.combine(session.persistentModelID)
            hasher.combine(session.startedAt)
            hasher.combine(session.finishedAt)
            hasher.combine(session.actualDurationMin)
            hasher.combine(session.outcomeRaw)
        }
        hasher.combine(finishedCount)
        let key = hasher.finalize()
        if key == fingerprint { return cached }

        cached = sessions.filter { $0.finishedAt != nil }.map { $0.toSnapshot() }
        fingerprint = key
        generation += 1
        return cached
    }
}
