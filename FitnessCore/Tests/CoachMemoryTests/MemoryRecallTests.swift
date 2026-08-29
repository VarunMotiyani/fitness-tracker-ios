import Foundation
import Testing
import CoachMemory
import FitnessDomain

@Suite("MemoryRecall")
struct MemoryRecallTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func mem(
        id: UUID = UUID(),
        kind: MemoryKind = .observation,
        statement: String = "stmt",
        action: String? = nil,
        confidence: Double = 0.5,
        lastConfirmedAt: Date? = nil,
        tags: MemoryTags = MemoryTags(),
        outcomeScore: Double? = nil,
        supersededBy: UUID? = nil,
        retiredByCap: Bool = false
    ) -> CoachMemory {
        CoachMemory(
            id: id,
            kind: kind,
            statement: statement,
            action: action,
            confidence: confidence,
            source: .agent("test"),
            createdAt: now,
            lastConfirmedAt: lastConfirmedAt ?? now,
            supersededBy: supersededBy,
            tags: tags,
            outcomeScore: outcomeScore,
            retiredByCap: retiredByCap
        )
    }

    @Test("a preference with no tags is always selected")
    func preferenceAlwaysSelected() {
        let p = mem(kind: .preference)
        let result = MemoryRecall.select(from: [p], context: RecallContext(), now: now)
        #expect(result.selected.map(\.id) == [p.id])
    }

    @Test("a goal with no tags is globally relevant")
    func goalAlwaysSelected() {
        let g = mem(kind: .goal)
        let result = MemoryRecall.select(from: [g], context: RecallContext(), now: now)
        #expect(result.selected.map(\.id) == [g.id])
    }

    @Test("a constraint with no tags is globally relevant")
    func constraintAlwaysSelected() {
        let c = mem(kind: .constraint)
        let result = MemoryRecall.select(from: [c], context: RecallContext(), now: now)
        #expect(result.selected.map(\.id) == [c.id])
    }

    @Test("a superseded memory is never selected")
    func supersededExcluded() {
        let m = mem(kind: .preference, supersededBy: UUID())
        let result = MemoryRecall.select(from: [m], context: RecallContext(), now: now)
        #expect(result.selected.isEmpty)
    }

    @Test("a cap-retired memory is never selected")
    func retiredByCapExcluded() {
        let m = mem(kind: .preference, retiredByCap: true)
        let result = MemoryRecall.select(from: [m], context: RecallContext(), now: now)
        #expect(result.selected.isEmpty)
    }

    @Test("an observation tagged muscle .chest is selected only when context has .chest")
    func observationMuscleGate() {
        let o = mem(kind: .observation, tags: MemoryTags(muscle: .chest))

        let hit = MemoryRecall.select(
            from: [o],
            context: RecallContext(muscles: [.chest]),
            now: now
        )
        #expect(hit.selected.map(\.id) == [o.id])

        let miss = MemoryRecall.select(
            from: [o],
            context: RecallContext(muscles: [.back]),
            now: now
        )
        #expect(miss.selected.isEmpty)
    }

    @Test("given equal confidence, the more recently confirmed memory ranks first")
    func recencyBreaksRank() {
        let recent = mem(
            kind: .preference,
            statement: "recent",
            confidence: 0.5,
            lastConfirmedAt: now.addingTimeInterval(-86_400)
        )
        let stale = mem(
            kind: .preference,
            statement: "stale",
            confidence: 0.5,
            lastConfirmedAt: now.addingTimeInterval(-40 * 86_400)
        )
        let result = MemoryRecall.select(from: [stale, recent], context: RecallContext(), now: now)
        #expect(result.selected.map(\.statement) == ["recent", "stale"])
    }

    @Test("a memory with outcomeScore 1 outranks an identical one with outcomeScore -1")
    func outcomeBreaksRank() {
        let good = mem(kind: .preference, statement: "good", confidence: 0.5, outcomeScore: 1)
        let bad = mem(kind: .preference, statement: "bad", confidence: 0.5, outcomeScore: -1)
        let result = MemoryRecall.select(from: [bad, good], context: RecallContext(), now: now)
        #expect(result.selected.map(\.statement) == ["good", "bad"])
    }

    @Test("maxItems 2 returns exactly 2")
    func maxItemsCap() {
        let a = mem(kind: .preference, statement: "a", confidence: 0.9)
        let b = mem(kind: .preference, statement: "b", confidence: 0.8)
        let c = mem(kind: .preference, statement: "c", confidence: 0.7)
        let d = mem(kind: .preference, statement: "d", confidence: 0.6)
        let result = MemoryRecall.select(
            from: [a, b, c, d],
            context: RecallContext(),
            now: now,
            maxItems: 2
        )
        #expect(result.selected.count == 2)
        #expect(result.selected.map(\.statement) == ["a", "b"])
    }

    @Test("digest contains only confidence >= 0.6 lines, formatted with the action arrow")
    func digestFiltersAndFormats() {
        let high = mem(
            kind: .preference,
            statement: "Prefers morning sessions",
            action: "Schedule lifts before noon",
            confidence: 0.8
        )
        let low = mem(
            kind: .preference,
            statement: "Might like supersets",
            action: "Try a superset block",
            confidence: 0.4
        )
        let result = MemoryRecall.select(from: [high, low], context: RecallContext(), now: now)
        #expect(result.selected.count == 2)
        #expect(result.digest == "- Prefers morning sessions → Schedule lifts before noon")
    }
}
