import Foundation
import Testing
import CoachMemory
import FitnessDomain

@Suite("MemoryConsolidation")
struct MemoryConsolidationTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let emptyTags = MemoryTags()

    private func memory(
        id: UUID = UUID(),
        kind: MemoryKind = .observation,
        statement: String = "stmt",
        action: String? = nil,
        confidence: Double,
        createdAt: Date,
        lastConfirmedAt: Date
    ) -> CoachMemory {
        CoachMemory(
            id: id,
            kind: kind,
            statement: statement,
            action: action,
            confidence: confidence,
            source: .agent("memoryKeeper"),
            createdAt: createdAt,
            lastConfirmedAt: lastConfirmedAt,
            supersededBy: nil,
            tags: MemoryTags(),
            outcomeScore: nil
        )
    }

    @Test("new candidate on empty store yields one write at newConfidence with now timestamps")
    func newOnEmptyStore() {
        let candidate = MemoryCandidate(
            kind: .observation,
            statement: "User trained legs Monday",
            action: nil,
            tags: emptyTags,
            relation: .new
        )

        let result = MemoryConsolidation.reconcile(existing: [], candidates: [candidate], now: now)

        #expect(result.writes.count == 1)
        #expect(result.updated.isEmpty)
        #expect(result.retired.isEmpty)
        let write = result.writes[0]
        #expect(write.confidence == 0.3)
        #expect(write.createdAt == now)
        #expect(write.lastConfirmedAt == now)
        #expect(write.statement == "User trained legs Monday")
        #expect(write.source == .agent("memoryKeeper"))
        #expect(write.supersededBy == nil)
        #expect(write.retiredByCap == false)
    }

    @Test("reinforces an existing memory bumps confidence and lastConfirmedAt without a write")
    func reinforcesExisting() {
        let existingID = UUID()
        let old = memory(
            id: existingID,
            confidence: 0.5,
            createdAt: now.addingTimeInterval(-10_000),
            lastConfirmedAt: now.addingTimeInterval(-5_000)
        )
        let candidate = MemoryCandidate(
            kind: .observation,
            statement: "stmt",
            action: nil,
            tags: emptyTags,
            relation: .reinforces(existingID)
        )

        let result = MemoryConsolidation.reconcile(existing: [old], candidates: [candidate], now: now)

        #expect(result.writes.isEmpty)
        #expect(result.retired.isEmpty)
        #expect(result.updated.count == 1)
        let updated = result.updated[0]
        #expect(updated.id == existingID)
        #expect(abs(updated.confidence - 0.65) < 1e-9)
        #expect(updated.lastConfirmedAt == now)
    }

    @Test("reinforces an unknown id falls through to a write")
    func reinforcesUnknownID() {
        let candidate = MemoryCandidate(
            kind: .observation,
            statement: "orphan",
            action: nil,
            tags: emptyTags,
            relation: .reinforces(UUID())
        )

        let result = MemoryConsolidation.reconcile(existing: [], candidates: [candidate], now: now)

        #expect(result.writes.count == 1)
        #expect(result.updated.isEmpty)
        #expect(result.retired.isEmpty)
        #expect(result.writes[0].confidence == 0.3)
        #expect(result.writes[0].statement == "orphan")
    }

    @Test("contradicts retires the old memory pointing at the new memory's id")
    func contradictsExisting() {
        let existingID = UUID()
        let old = memory(
            id: existingID,
            statement: "old belief",
            confidence: 0.8,
            createdAt: now.addingTimeInterval(-10_000),
            lastConfirmedAt: now.addingTimeInterval(-5_000)
        )
        let candidate = MemoryCandidate(
            kind: .observation,
            statement: "new belief",
            action: nil,
            tags: emptyTags,
            relation: .contradicts(existingID)
        )

        let result = MemoryConsolidation.reconcile(existing: [old], candidates: [candidate], now: now)

        #expect(result.writes.count == 1)
        #expect(result.updated.isEmpty)
        #expect(result.retired.count == 1)
        let newMemory = result.writes[0]
        let retired = result.retired[0]
        #expect(newMemory.statement == "new belief")
        #expect(newMemory.confidence == 0.3)
        #expect(retired.id == existingID)
        #expect(retired.supersededBy == newMemory.id)
        #expect(retired.isRetired)
    }

    @Test("per-kind cap retires the lowest-confidence excess via retiredByCap")
    func perKindCapEviction() {
        var existing: [CoachMemory] = []
        for i in 0..<13 {
            existing.append(
                memory(
                    id: UUID(),
                    statement: "obs \(i)",
                    confidence: 0.2 + Double(i) * 0.05,
                    createdAt: now.addingTimeInterval(-Double(i) * 1_000),
                    lastConfirmedAt: now.addingTimeInterval(-Double(i) * 1_000)
                )
            )
        }
        // lowest confidence: i=0 (0.20) and i=1 (0.25)
        let lowestID = existing[0].id
        let secondLowestID = existing[1].id

        let candidate = MemoryCandidate(
            kind: .observation,
            statement: "fresh obs",
            action: nil,
            tags: emptyTags,
            relation: .new
        )

        let result = MemoryConsolidation.reconcile(
            existing: existing,
            candidates: [candidate],
            now: now,
            perKindCap: 12
        )

        // 13 existing + 1 write = 14; cap 12 -> 2 evicted
        #expect(result.writes.count == 1)
        #expect(result.retired.count == 2)
        #expect(result.retired.allSatisfy { $0.retiredByCap })
        let retiredIDs = Set(result.retired.map(\.id))
        #expect(retiredIDs == [lowestID, secondLowestID])
    }

    @Test("output arrays are sorted by createdAt then id")
    func outputsAreSorted() {
        let idA = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        let idB = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!
        let old1 = memory(
            id: idB,
            kind: .preference,
            statement: "b",
            confidence: 0.5,
            createdAt: now.addingTimeInterval(-1_000),
            lastConfirmedAt: now.addingTimeInterval(-1_000)
        )
        let old2 = memory(
            id: idA,
            kind: .preference,
            statement: "a",
            confidence: 0.5,
            createdAt: now.addingTimeInterval(-1_000),
            lastConfirmedAt: now.addingTimeInterval(-1_000)
        )
        let candidates = [
            MemoryCandidate(kind: .preference, statement: "b", action: nil, tags: emptyTags, relation: .reinforces(idB)),
            MemoryCandidate(kind: .preference, statement: "a", action: nil, tags: emptyTags, relation: .reinforces(idA)),
        ]

        let result = MemoryConsolidation.reconcile(existing: [old1, old2], candidates: candidates, now: now)

        #expect(result.updated.count == 2)
        // same createdAt -> id ascending: idA (…AA) before idB (…BB)
        #expect(result.updated[0].id == idA)
        #expect(result.updated[1].id == idB)
        let arrays: [[CoachMemory]] = [result.writes, result.updated, result.retired]
        for arr in arrays {
            let sorted: [CoachMemory] = arr.sorted { (a: CoachMemory, b: CoachMemory) -> Bool in
                if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
                return a.id.uuidString < b.id.uuidString
            }
            #expect(arr == sorted)
        }
    }
}
