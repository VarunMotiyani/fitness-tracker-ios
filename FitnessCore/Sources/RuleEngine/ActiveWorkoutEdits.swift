import Foundation

public enum ActiveWorkoutEdits {
    public static func canMoveUnit(entries: [RunnerEntry], index: Int, direction: Int) -> Bool {
        let allUnits = SupersetFlow.units(entries)
        guard let unitIdx = allUnits.firstIndex(where: { $0.contains(index) }) else { return false }
        let targetUnitIdx = unitIdx + direction
        return targetUnitIdx >= 0 && targetUnitIdx < allUnits.count
    }

    public static func moveUnit(
        entries: inout [RunnerEntry],
        index: Int,
        direction: Int
    ) -> (newOrder: [Int], newCurrent: Int)? {
        let allUnits = SupersetFlow.units(entries)
        guard let unitIdx = allUnits.firstIndex(where: { $0.contains(index) }) else { return nil }
        let targetUnitIdx = unitIdx + direction
        guard targetUnitIdx >= 0 && targetUnitIdx < allUnits.count else { return nil }

        var reorderedUnits = allUnits
        let movedUnit = reorderedUnits.remove(at: unitIdx)
        reorderedUnits.insert(movedUnit, at: targetUnitIdx)

        let flatOldIndices = reorderedUnits.flatMap { $0 }
        let reorderedEntries = flatOldIndices.map { entries[$0] }
        entries = reorderedEntries

        let newCurrent = flatOldIndices.firstIndex(of: index) ?? index
        return (newOrder: flatOldIndices, newCurrent: newCurrent)
    }

    public enum GroupDisposition: Sendable, Codable, Equatable {
        case keep, detach
    }

    public enum SwapResult: Sendable, Equatable {
        case replacedInPlace(index: Int)
        case needsConfirmation(grouped: Bool, index: Int)
        case inserted(index: Int)
    }

    public static func swap(
        entries: inout [RunnerEntry],
        index: Int,
        replacement: RunnerEntry,
        loggedConfirmed: Bool = false,
        groupDisposition: GroupDisposition? = nil
    ) -> SwapResult {
        guard index >= 0 && index < entries.count else {
            return .replacedInPlace(index: index)
        }
        let target = entries[index]
        let hasLoggedWork = target.sets.contains { $0.done }

        if !hasLoggedWork {
            // Replace in place, keeping supersetID
            var rep = replacement
            rep.supersetID = target.supersetID
            entries[index] = rep
            return .replacedInPlace(index: index)
        }

        if !loggedConfirmed {
            return .needsConfirmation(grouped: target.supersetID != nil, index: index)
        }

        // Confirmed: insert replacement adjacent to target
        var rep = replacement
        let isGrouped = target.supersetID != nil
        if isGrouped && groupDisposition == .keep {
            rep.supersetID = target.supersetID
            let insertIdx = index + 1
            entries.insert(rep, at: insertIdx)
            return .inserted(index: insertIdx)
        } else {
            // Detached: insert after the whole unit
            rep.supersetID = nil
            let allUnits = SupersetFlow.units(entries)
            let insertIdx = SupersetFlow.insertionIndexAfterUnit(units: allUnits, current: index, entryCount: entries.count)
            entries.insert(rep, at: insertIdx)
            return .inserted(index: insertIdx)
        }
    }
}
