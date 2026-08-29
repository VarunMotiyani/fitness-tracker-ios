import Foundation

/// A proposed change to the coach's memory, as decided by the caller (the
/// memory-keeper LLM call in Phase 2c). `reconcile` applies these deterministically.
public struct MemoryCandidate: Sendable, Equatable {
    public let kind: MemoryKind
    public let statement: String
    public let action: String?
    public let tags: MemoryTags
    public let relation: CandidateRelation

    public init(
        kind: MemoryKind,
        statement: String,
        action: String?,
        tags: MemoryTags,
        relation: CandidateRelation
    ) {
        self.kind = kind
        self.statement = statement
        self.action = action
        self.tags = tags
        self.relation = relation
    }
}

/// How a candidate relates to the existing memory set.
public enum CandidateRelation: Sendable, Equatable {
    case new
    case reinforces(UUID)
    case contradicts(UUID)
}

/// The deterministic outcome of `MemoryConsolidation.reconcile`.
public struct ConsolidationResult: Sendable, Equatable {
    public let writes: [CoachMemory]
    public let updated: [CoachMemory]
    public let retired: [CoachMemory]

    public init(writes: [CoachMemory], updated: [CoachMemory], retired: [CoachMemory]) {
        self.writes = writes
        self.updated = updated
        self.retired = retired
    }
}

public enum MemoryConsolidation {
    /// Applies `candidates` to `existing` and returns the resulting write / reinforce
    /// / retire / cap-evict sets. Pure and deterministic: exactly one `UUID()` per
    /// `.new` / `.contradicts` candidate (and per unknown-id `.reinforces`), and all
    /// output arrays sorted by `createdAt` then `id`.
    public static func reconcile(
        existing: [CoachMemory],
        candidates: [MemoryCandidate],
        now: Date,
        perKindCap: Int = 12,
        reinforceStep: Double = 0.15,
        newConfidence: Double = 0.3
    ) -> ConsolidationResult {
        var writes: [CoachMemory] = []
        var updated: [CoachMemory] = []
        var retired: [CoachMemory] = []

        // Existing memories consumed by a candidate (reinforced or contradicted);
        // excluded from the cap's "existing not otherwise retired/updated" pool.
        var consumedExistingIDs: Set<UUID> = []

        func freshMemory(from candidate: MemoryCandidate) -> CoachMemory {
            CoachMemory(
                id: UUID(),
                kind: candidate.kind,
                statement: candidate.statement,
                action: candidate.action,
                confidence: newConfidence,
                source: .agent("memoryKeeper"),
                createdAt: now,
                lastConfirmedAt: now,
                supersededBy: nil,
                tags: candidate.tags,
                outcomeScore: nil,
                retiredByCap: false
            )
        }

        for candidate in candidates {
            switch candidate.relation {
            case .new:
                writes.append(freshMemory(from: candidate))

            case .reinforces(let id):
                guard let match = existing.first(where: { $0.id == id }) else {
                    // Unknown id -> treat exactly as `.new`.
                    writes.append(freshMemory(from: candidate))
                    continue
                }
                var copy = match
                copy.confidence = min(1, copy.confidence + reinforceStep)
                copy.lastConfirmedAt = now
                if let action = candidate.action, !action.isEmpty, copy.action == nil {
                    copy.action = action
                }
                consumedExistingIDs.insert(id)
                updated.append(copy)

            case .contradicts(let id):
                let fresh = freshMemory(from: candidate)
                writes.append(fresh)
                if let match = existing.first(where: { $0.id == id }) {
                    var copy = match
                    copy.supersededBy = fresh.id
                    consumedExistingIDs.insert(id)
                    retired.append(copy)
                }
            }
        }

        // --- Per-kind cap ------------------------------------------------------
        var evictedWriteIDs: Set<UUID> = []
        var evictedUpdatedIDs: Set<UUID> = []

        for kind in MemoryKind.allCases {
            let liveExisting = existing.filter {
                $0.kind == kind
                    && !consumedExistingIDs.contains($0.id)
                    && !$0.isRetired
                    && !$0.retiredByCap
            }
            let liveWrites = writes.filter { $0.kind == kind && !$0.isRetired && !$0.retiredByCap }
            let liveUpdated = updated.filter { $0.kind == kind && !$0.isRetired && !$0.retiredByCap }

            let count = liveExisting.count + liveWrites.count + liveUpdated.count
            guard count > perKindCap else { continue }
            let excess = count - perKindCap

            var pool = liveExisting + liveWrites + liveUpdated
            pool.sort { lhs, rhs in
                if lhs.confidence != rhs.confidence { return lhs.confidence < rhs.confidence }
                if lhs.lastConfirmedAt != rhs.lastConfirmedAt { return lhs.lastConfirmedAt < rhs.lastConfirmedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }

            for victim in pool.prefix(excess) {
                var evicted = victim
                evicted.retiredByCap = true
                retired.append(evicted)
                if writes.contains(where: { $0.id == victim.id }) {
                    evictedWriteIDs.insert(victim.id)
                } else if updated.contains(where: { $0.id == victim.id }) {
                    evictedUpdatedIDs.insert(victim.id)
                }
            }
        }

        writes.removeAll { evictedWriteIDs.contains($0.id) }
        updated.removeAll { evictedUpdatedIDs.contains($0.id) }

        return ConsolidationResult(
            writes: sortedForOutput(writes),
            updated: sortedForOutput(updated),
            retired: sortedForOutput(retired)
        )
    }

    private static func sortedForOutput(_ memories: [CoachMemory]) -> [CoachMemory] {
        memories.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
