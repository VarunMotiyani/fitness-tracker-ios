import Foundation

public enum OneRMFormula: String, Sendable, Codable, CaseIterable {
    case epley, brzycki, lombardi
}

public enum Estimated1RM {
    public static let repCap = 12

    public static func estimate(loadKg: Double, reps: Int, formula: OneRMFormula = .epley) -> Double? {
        guard loadKg > 0, reps >= 1, reps <= repCap, !loadKg.isNaN, !loadKg.isInfinite else {
            return nil
        }
        if reps == 1 {
            return (loadKg * 10).rounded() / 10.0
        }
        let raw: Double
        switch formula {
        case .epley:
            raw = loadKg * (1.0 + Double(reps) / 30.0)
        case .brzycki:
            raw = reps < 37 ? loadKg * 36.0 / (37.0 - Double(reps)) : (loadKg * (1.0 + Double(reps) / 30.0))
        case .lombardi:
            raw = loadKg * pow(Double(reps), 0.10)
        }
        guard !raw.isNaN, !raw.isInfinite else { return nil }
        return (raw * 10).rounded() / 10.0
    }

    /// Uncapped Epley estimate for internal ranking (PR detection, rollups, recovery
    /// stimulus). Unlike `estimate(_:)` this does NOT apply `repCap` — a 15-rep set still
    /// gets a real number rather than collapsing to 0 — because these callers only need a
    /// consistent ordering, not a display-quality 1RM.
    public static func epley(loadKg: Double, reps: Int) -> Double {
        guard loadKg > 0, reps >= 1, loadKg.isFinite else { return 0 }
        if reps == 1 { return (loadKg * 10).rounded() / 10.0 }
        return ((loadKg * (1.0 + Double(reps) / 30.0)) * 10).rounded() / 10.0
    }

    public static func bestSet(
        in entry: CompletedEntrySnapshot,
        formula: OneRMFormula = .epley
    ) -> (est: Double, loadKg: Double, reps: Int)? {
        var best: (est: Double, loadKg: Double, reps: Int)? = nil
        for s in entry.sets where s.isWorkingSet && s.actualReps > 0 && s.actualLoadKg > 0 {
            guard let est = estimate(loadKg: s.actualLoadKg, reps: s.actualReps, formula: formula) else {
                continue
            }
            if let cur = best {
                if est > cur.est {
                    best = (est: est, loadKg: s.actualLoadKg, reps: s.actualReps)
                }
            } else {
                best = (est: est, loadKg: s.actualLoadKg, reps: s.actualReps)
            }
        }
        return best
    }

    public static func series(
        exerciseID: String,
        sessions: [CompletedSessionSnapshot],
        formula: OneRMFormula = .epley
    ) -> [(date: Date, est: Double, loadKg: Double, reps: Int)] {
        let sorted = sessions.sorted { $0.date < $1.date }
        var result: [(date: Date, est: Double, loadKg: Double, reps: Int)] = []
        for session in sorted {
            guard let entry = session.entries.first(where: { $0.exerciseID == exerciseID }),
                  let best = bestSet(in: entry, formula: formula) else {
                continue
            }
            result.append((date: session.date, est: best.est, loadKg: best.loadKg, reps: best.reps))
        }
        return result
    }

    public static func best(
        exerciseID: String,
        sessions: [CompletedSessionSnapshot],
        formula: OneRMFormula = .epley
    ) -> (est: Double, loadKg: Double, reps: Int, date: Date)? {
        let all = series(exerciseID: exerciseID, sessions: sessions, formula: formula)
        guard let top = all.max(by: { $0.est < $1.est }) else { return nil }
        return (est: top.est, loadKg: top.loadKg, reps: top.reps, date: top.date)
    }

    public static func isRecord(
        exerciseID: String,
        entry: CompletedEntrySnapshot,
        priorSessions: [CompletedSessionSnapshot],
        formula: OneRMFormula = .epley
    ) -> (est: Double, loadKg: Double, reps: Int, previous: Double)? {
        guard let currentBest = bestSet(in: entry, formula: formula) else { return nil }
        let priorBest = best(exerciseID: exerciseID, sessions: priorSessions, formula: formula)
        let prevEst = priorBest?.est ?? 0.0
        if currentBest.est > prevEst {
            return (est: currentBest.est, loadKg: currentBest.loadKg, reps: currentBest.reps, previous: prevEst)
        }
        return nil
    }
}
