import Foundation
import FitnessDomain
import Metrics

/// How an exercise is logged.
public enum LoggingMode: String, Sendable, Codable, Equatable {
    /// Reps against a load. Sets are `load × reps`.
    case reps
    /// A held duration (planks, hangs, loaded carries). Sets are `seconds` (and an optional load).
    case time
    /// Duration + speed (treadmill, bike). Progressed manually.
    case cardio
}

/// The numbers an exercise was prescribed for one session — what the progression engine
/// judges the logged result against.
public struct ProgressionTarget: Sendable, Equatable {
    public var mode: LoggingMode
    public var sets: Int
    /// Target reps (reps mode). For a rep-range policy this is the top of the range.
    public var reps: Int
    /// Bottom of a rep range (double progression); `nil` for single-target policies.
    public var repsMin: Int?
    /// Rep ceiling: the range top, or the point past which bodyweight work adds a set
    /// instead of a rep. `nil` when there is no ceiling.
    public var repsMax: Int?
    /// Target hold in seconds (time mode).
    public var sec: Int
    /// Current working load in kg. `nil` or `0` means bodyweight (nothing to add or remove).
    public var loadKg: Double?
    /// Unilateral movement: rep targets and rep steps move in twos so both sides get the rep.
    public var perSide: Bool
    /// Per-exercise load-increment override in kg. `nil` uses the mechanic/body-part default.
    public var incKg: Double?
    /// Progression policy override
    public var policy: ProgressionPolicy?

    public init(
        mode: LoggingMode = .reps,
        sets: Int = 3,
        reps: Int = 10,
        repsMin: Int? = nil,
        repsMax: Int? = nil,
        sec: Int = 45,
        loadKg: Double? = nil,
        perSide: Bool = false,
        incKg: Double? = nil,
        policy: ProgressionPolicy? = nil
    ) {
        self.mode = mode
        self.sets = sets
        self.reps = reps
        self.repsMin = repsMin
        self.repsMax = repsMax
        self.sec = sec
        self.loadKg = loadKg
        self.perSide = perSide
        self.incKg = incKg
        self.policy = policy
    }

    /// The rep step for this exercise: 2 for unilateral work, 1 otherwise.
    public var repStep: Int { perSide ? 2 : 1 }
}

public typealias PrescriptionTarget = ProgressionTarget

/// One completed exercise entry, reduced to what a progression policy needs to judge it.
///
/// Warm-up sets are dropped before anything is measured. A logged set is a *hit* only when
/// it was performed at or above the goal; a set performed with fewer reps, and a set that
/// was never performed, are both misses; and logging fewer sets than the plan asked for is
/// a miss regardless of the sets that were done. So a session that fell apart can never
/// read as a success.
public struct SessionReading: Sendable, Equatable {
    public let mode: LoggingMode
    public let date: Date
    /// Target reps (reps mode) or target seconds (time mode).
    public let goal: Int
    /// Reps for each work set in order; `0` for a set that was not performed.
    public let repsPerSet: [Int]
    /// Held seconds for each work set in order; `0` for a set that was not performed.
    public let heldPerSet: [Int]
    /// Heaviest load across the performed work sets, in kg.
    public let weightKg: Double
    /// Count of work sets logged — the dimension bodyweight training grows in.
    public let count: Int
    /// Fewest reps in any performed work set (`0` when none were performed).
    public let low: Int
    /// Reps on the last work set — the "as many as possible" set for AMRAP-style policies.
    public let amrap: Int
    /// Every prescribed set was performed at or above the goal.
    public let ok: Bool

    public init(
        mode: LoggingMode,
        date: Date = Date(),
        goal: Int,
        repsPerSet: [Int] = [],
        heldPerSet: [Int] = [],
        weightKg: Double,
        count: Int,
        low: Int = 0,
        amrap: Int = 0,
        ok: Bool
    ) {
        self.mode = mode
        self.date = date
        self.goal = goal
        self.repsPerSet = repsPerSet
        self.heldPerSet = heldPerSet
        self.weightKg = weightKg
        self.count = count
        self.low = low
        self.amrap = amrap
        self.ok = ok
    }

    public var weight: Double { weightKg }
}

public enum SessionReadingReducer {
    /// A set counts as *performed* once it has real reps (or, in time mode, a held duration)
    /// on it — the app never stores a per-set "done" flag separate from the numbers.
    private static func performed(_ set: LoggedSetSnapshot, timed: Bool) -> Bool {
        timed ? (set.heldSec ?? 0) > 0 : set.actualReps > 0
    }

    /// Reduce one completed entry to a `SessionReading`.
    ///
    /// - `target` supplies `mode`, planned `sets`, and the `goal`. When its `sets` is not
    ///   positive, `fallbackTarget` (the exercise's current plan) is consulted — old logs
    ///   predate storing the prescription and would otherwise score as misses forever.
    public static func read(
        entry: CompletedEntrySnapshot,
        target: ProgressionTarget,
        fallbackTarget: ProgressionTarget?,
        date: Date
    ) -> SessionReading {
        let t = target.sets > 0 ? target : (fallbackTarget ?? target)
        let timed = t.mode == .time
        let work = entry.sets.filter { !$0.isWarmup }
        let plannedSets = t.sets > 0 ? t.sets : work.count
        let enough = work.count >= plannedSets

        if timed {
            let goal = t.sec
            let held = work.map { performed($0, timed: true) ? ($0.heldSec ?? 0) : 0 }
            let weight = work.filter { performed($0, timed: true) }.map(\.actualLoadKg).max() ?? 0
            let ok = goal > 0 && enough && !held.isEmpty && held.allSatisfy { $0 >= goal }
            return SessionReading(
                mode: .time, date: date, goal: goal,
                repsPerSet: [], heldPerSet: held, weightKg: weight,
                count: held.count, low: held.min() ?? 0, amrap: held.last ?? 0, ok: ok
            )
        }

        let goal = t.reps
        let reps = work.map { performed($0, timed: false) ? $0.actualReps : 0 }
        let weight = work.filter { performed($0, timed: false) }.map(\.actualLoadKg).max() ?? 0
        let ok = goal > 0 && enough && !reps.isEmpty && reps.allSatisfy { $0 >= goal }
        return SessionReading(
            mode: t.mode, date: date, goal: goal,
            repsPerSet: reps, heldPerSet: [], weightKg: weight,
            count: reps.count, low: reps.min() ?? 0, amrap: reps.last ?? 0, ok: ok
        )
    }

    /// Oldest-first readings for one exercise across a session history.
    ///
    /// Sessions flagged `excludeFromProgression` are real history for stats but never a
    /// baseline for the next prescription, so they are skipped here. Entries with no
    /// performed work set are skipped too. Per-entry prescriptions are not stored, so every
    /// past entry is judged against `currentTarget` (the documented fallback).
    public static func history(
        exerciseID: String,
        sessions: [CompletedSessionSnapshot],
        currentTarget: ProgressionTarget
    ) -> [SessionReading] {
        sessions
            .filter { !$0.excludeFromProgression }
            .sorted { $0.date < $1.date }
            .compactMap { session in
                guard let entry = session.entries.first(where: { $0.exerciseID == exerciseID }),
                      entry.sets.contains(where: { !$0.isWarmup && ($0.actualReps > 0 || ($0.heldSec ?? 0) > 0) })
                else { return nil }
                return read(entry: entry, target: currentTarget, fallbackTarget: currentTarget, date: session.date)
            }
    }

    /// Consecutive non-`ok` readings counting back from the most recent.
    public static func stallCount(_ readings: [SessionReading]) -> Int {
        var n = 0
        for reading in readings.reversed() {
            if reading.ok { break }
            n += 1
        }
        return n
    }
}
