import Foundation

public struct RunnerSetRow: Sendable, Equatable {
    public var done: Bool
    public var isWarmup: Bool

    public init(done: Bool = false, isWarmup: Bool = false) {
        self.done = done
        self.isWarmup = isWarmup
    }
}

public struct RunnerEntry: Sendable, Equatable, Identifiable {
    public var id: String
    public var supersetID: String?
    public var restSec: Int?
    public var sets: [RunnerSetRow]

    public init(
        id: String,
        supersetID: String? = nil,
        restSec: Int? = nil,
        sets: [RunnerSetRow] = []
    ) {
        self.id = id
        self.supersetID = supersetID
        self.restSec = restSec
        self.sets = sets
    }
}

public enum SupersetFlow {
    /// Group consecutive entries sharing a non-nil supersetID into units of entry indices.
    /// Entries with nil supersetID each form their own 1-element unit.
    public static func units(_ entries: [RunnerEntry]) -> [[Int]] {
        var result: [[Int]] = []
        var currentGroup: [Int] = []
        var currentSupersetID: String? = nil

        for (idx, entry) in entries.enumerated() {
            if let sid = entry.supersetID {
                if sid == currentSupersetID {
                    currentGroup.append(idx)
                } else {
                    if !currentGroup.isEmpty {
                        result.append(currentGroup)
                    }
                    currentGroup = [idx]
                    currentSupersetID = sid
                }
            } else {
                if !currentGroup.isEmpty {
                    result.append(currentGroup)
                    currentGroup = []
                    currentSupersetID = nil
                }
                result.append([idx])
            }
        }
        if !currentGroup.isEmpty {
            result.append(currentGroup)
        }
        return result
    }

    /// First unfinished unit after `from` index in units list, wrapping once.
    public static func nextUnfinishedUnit(_ entries: [RunnerEntry], units: [[Int]], from: Int) -> [Int]? {
        guard !units.isEmpty else { return nil }
        let total = units.count
        for i in 1...total {
            let uIdx = (from + i) % total
            let unit = units[uIdx]
            let isUnfinished = unit.contains { eIdx in
                entries[eIdx].sets.contains { !$0.done }
            }
            if isUnfinished {
                return unit
            }
        }
        return nil
    }

    /// Insert index after the unit containing `current` (clamped to count).
    public static func insertionIndexAfterUnit(units: [[Int]], current: Int, entryCount: Int) -> Int {
        for unit in units {
            if unit.contains(current) {
                let maxIdx = unit.max() ?? current
                return min(entryCount, maxIdx + 1)
            }
        }
        return min(entryCount, current + 1)
    }

    /// New progress only when done-set count exceeds the session high-water for this entry.
    public static func progress(entry: RunnerEntry, previousHighWater: Int) -> (isNew: Bool, highWater: Int) {
        let doneCount = entry.sets.filter(\.done).count
        if doneCount > previousHighWater {
            return (isNew: true, highWater: doneCount)
        } else {
            return (isNew: false, highWater: previousHighWater)
        }
    }

    /// Whether completing a set starts a rest: after every set EXCEPT the last set of the last unit.
    public static func restAfterSet(unitDone: Bool, lastUnit: Bool) -> Bool {
        if unitDone && lastUnit {
            return false
        }
        return true
    }

    /// Whether re-checking a done set starts a rest: only when no timer is running and restAfterSet would.
    public static func restOnRecheck(timerRunning: Bool, unitDone: Bool, lastUnit: Bool) -> Bool {
        guard !timerRunning else { return false }
        return restAfterSet(unitDone: unitDone, lastUnit: lastUnit)
    }

    /// Rest seconds for a completed set's unit: the LONGEST per-entry `restSec` among the
    /// unit's members, falling back to `defaultRestSec`. `defaultRestSec == 0` = off, but a
    /// per-entry value still fires.
    public static func restSeconds(entries: [RunnerEntry], unit: [Int], defaultRestSec: Int) -> Int {
        let memberRests = unit.compactMap { idx in
            idx < entries.count ? entries[idx].restSec : nil
        }
        if let maxMember = memberRests.max(), maxMember > 0 {
            return maxMember
        }
        return defaultRestSec
    }

    /// Next index within a superset unit after finishing `from`: skips spent members, wraps,
    /// reports `roundDone` / `unitDone`.
    public static func step(entries: [RunnerEntry], unit: [Int], from: Int) -> (unitDone: Bool, roundDone: Bool, nextIdx: Int?)? {
        guard !unit.isEmpty else { return nil }
        guard let currentPosInUnit = unit.firstIndex(of: from) else { return nil }

        let allUnitDone = unit.allSatisfy { idx in
            entries[idx].sets.allSatisfy(\.done)
        }
        if allUnitDone {
            return (unitDone: true, roundDone: true, nextIdx: nil)
        }

        let unitSize = unit.count
        for step in 1...unitSize {
            let nextPos = (currentPosInUnit + step) % unitSize
            let targetEntryIdx = unit[nextPos]
            let hasUndone = entries[targetEntryIdx].sets.contains { !$0.done }
            if hasUndone {
                let roundDone = (nextPos <= currentPosInUnit)
                return (unitDone: false, roundDone: roundDone, nextIdx: targetEntryIdx)
            }
        }

        return (unitDone: true, roundDone: true, nextIdx: nil)
    }
}
