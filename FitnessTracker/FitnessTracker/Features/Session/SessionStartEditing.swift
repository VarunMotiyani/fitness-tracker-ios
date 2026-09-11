import Foundation
import FitnessDomain

/// Mutable, session-scoped edits made on the setup screen.
///
/// The weekly plan remains the source of truth for future days. This draft is
/// copied into the started session only, so reordering or adding an exercise
/// today never changes the recurring plan.
nonisolated struct SessionStartDraft: Equatable {
    private(set) var items: [PlannedItem]

    init(items: [PlannedItem]) {
        self.items = items
    }

    mutating func moveUp(at index: Int) {
        guard items.indices.contains(index), index > items.startIndex else { return }
        items.swapAt(index, index - 1)
    }

    mutating func moveDown(at index: Int) {
        guard items.indices.contains(index), index < items.index(before: items.endIndex) else { return }
        items.swapAt(index, index + 1)
    }

    mutating func move(from source: Int, to destination: Int) {
        guard items.indices.contains(source), items.indices.contains(destination), source != destination else { return }
        let moved = items.remove(at: source)
        items.insert(moved, at: destination)
    }

    mutating func append(_ item: PlannedItem) {
        items.append(item)
    }

    @discardableResult
    mutating func remove(at index: Int) -> PlannedItem? {
        guard items.indices.contains(index) else { return nil }
        return items.remove(at: index)
    }

    mutating func replace(at index: Int, with exerciseID: String) {
        guard items.indices.contains(index) else { return }
        let item = items[index]
        items[index] = PlannedItem(
            exerciseID: exerciseID,
            targetSets: item.targetSets,
            targetReps: item.targetReps,
            targetLoadKg: item.targetLoadKg,
            restSeconds: item.restSeconds,
            coachNote: item.coachNote
        )
    }

    func plannedSession(basedOn session: PlannedSession) -> PlannedSession {
        PlannedSession(
            id: session.id,
            order: session.order,
            focusMuscles: session.focusMuscles,
            items: items
        )
    }
}

/// Deterministic planning rules shared by the setup UI and its tests. The
/// runner applies the same trailing-item trim during finalization.
nonisolated enum SessionStartPlanning {
    static func previewItems(_ items: [PlannedItem], minutes: Int) -> [PlannedItem] {
        var result = items
        var estimate = estimatedMinutes(for: result)
        while estimate > Double(minutes) && result.count > 1 {
            result.removeLast()
            estimate = estimatedMinutes(for: result)
        }
        return result
    }

    static func estimatedMinutes(for items: [PlannedItem]) -> Double {
        items.reduce(0.0) { $0 + Double($1.targetSets) * (40 + Double($1.restSeconds)) } / 60
    }
}
