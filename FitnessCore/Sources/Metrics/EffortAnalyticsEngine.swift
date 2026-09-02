import Foundation
import FitnessDomain
import ExerciseCatalog

public struct EffortSummary: Sendable, Codable, Equatable {
    public let ratedSets: Int
    public let totalSets: Int
    public let averageRIR: Double?
    public let hardSetsPercentage: Double?

    public init(ratedSets: Int, totalSets: Int, averageRIR: Double?, hardSetsPercentage: Double?) {
        self.ratedSets = ratedSets
        self.totalSets = totalSets
        self.averageRIR = averageRIR
        self.hardSetsPercentage = hardSetsPercentage
    }
}

public struct WeeklyEffortTrend: Sendable, Codable, Equatable, Identifiable {
    public var id: Date { weekStart }
    public let weekStart: Date
    public let averageRIR: Double
    public let setsCount: Int

    public init(weekStart: Date, averageRIR: Double, setsCount: Int) {
        self.weekStart = weekStart
        self.averageRIR = averageRIR
        self.setsCount = setsCount
    }
}

public struct EffortHistogramBin: Sendable, Codable, Equatable, Identifiable {
    public var id: String { label }
    public let rir: Int
    public let label: String
    public let count: Int
    public let percentage: Double
    public let isHard: Bool

    public init(rir: Int, label: String, count: Int, percentage: Double, isHard: Bool) {
        self.rir = rir
        self.label = label
        self.count = count
        self.percentage = percentage
        self.isHard = isHard
    }
}

public struct ExerciseLoggedPerformance: Sendable, Codable, Equatable, Identifiable {
    public var id: Date { date }
    public let date: Date
    public let topSetWeightKg: Double
    public let topSetReps: Int
    public let estimated1RM: Double
    public let formattedSets: String
    public let averageRIR: Double?

    public init(date: Date, topSetWeightKg: Double, topSetReps: Int, estimated1RM: Double, formattedSets: String, averageRIR: Double?) {
        self.date = date
        self.topSetWeightKg = topSetWeightKg
        self.topSetReps = topSetReps
        self.estimated1RM = estimated1RM
        self.formattedSets = formattedSets
        self.averageRIR = averageRIR
    }
}

public enum EffortAnalyticsEngine {
    public static func computeSummary(from sessions: [CompletedSessionSnapshot], windowDays: Int = 90, now: Date = .now) -> EffortSummary {
        let cal = Calendar.isoUTC
        let cutoff = windowDays > 0 ? cal.date(byAdding: .day, value: -windowDays, to: now) : nil

        var ratedCount = 0
        var totalCount = 0
        var rirSum = 0.0
        var hardCount = 0

        for session in sessions {
            if let cutoff, session.date < cutoff { continue }
            for entry in session.entries where entry.countsTowardMetrics {
                for set in entry.sets where set.isWorkingSet {
                    totalCount += 1
                    if let rpe = set.rpe {
                        let rir = 10.0 - rpe
                        ratedCount += 1
                        rirSum += rir
                        if rir <= 3.0 {
                            hardCount += 1
                        }
                    }
                }
            }
        }

        let avgRir = ratedCount > 0 ? (rirSum / Double(ratedCount)) : nil
        let hardPct = ratedCount > 0 ? (Double(hardCount) / Double(ratedCount)) : nil

        return EffortSummary(
            ratedSets: ratedCount,
            totalSets: totalCount,
            averageRIR: avgRir,
            hardSetsPercentage: hardPct
        )
    }

    public static func computeWeeklyTrends(from sessions: [CompletedSessionSnapshot], windowDays: Int = 90, now: Date = .now) -> [WeeklyEffortTrend] {
        let cal = Calendar.isoUTC
        let cutoff = windowDays > 0 ? cal.date(byAdding: .day, value: -windowDays, to: now) : nil

        var weeklyBuckets: [Date: (sumRIR: Double, count: Int, totalSets: Int)] = [:]

        for session in sessions {
            if let cutoff, session.date < cutoff { continue }
            guard let weekStart = cal.dateInterval(of: .weekOfYear, for: session.date)?.start else { continue }
            
            for entry in session.entries where entry.countsTowardMetrics {
                for set in entry.sets where set.isWorkingSet {
                    var bucket = weeklyBuckets[weekStart] ?? (sumRIR: 0.0, count: 0, totalSets: 0)
                    bucket.totalSets += 1
                    if let rpe = set.rpe {
                        let rir = 10.0 - rpe
                        bucket.sumRIR += rir
                        bucket.count += 1
                    }
                    weeklyBuckets[weekStart] = bucket
                }
            }
        }

        return weeklyBuckets.keys.sorted().compactMap { weekStart in
            guard let bucket = weeklyBuckets[weekStart], bucket.count > 0 else { return nil }
            return WeeklyEffortTrend(
                weekStart: weekStart,
                averageRIR: (bucket.sumRIR / Double(bucket.count) * 10).rounded() / 10,
                setsCount: bucket.totalSets
            )
        }
    }

    public static func computeHistogram(from sessions: [CompletedSessionSnapshot], windowDays: Int = 90, now: Date = .now) -> [EffortHistogramBin] {
        let cal = Calendar.isoUTC
        let cutoff = windowDays > 0 ? cal.date(byAdding: .day, value: -windowDays, to: now) : nil

        var bins = [0: 0, 1: 0, 2: 0, 3: 0, 4: 0]
        var totalRated = 0

        for session in sessions {
            if let cutoff, session.date < cutoff { continue }
            for entry in session.entries where entry.countsTowardMetrics {
                for set in entry.sets where set.isWorkingSet {
                    if let rpe = set.rpe {
                        let rir = max(0, Int((10.0 - rpe).rounded()))
                        let bucket = min(4, rir)
                        bins[bucket, default: 0] += 1
                        totalRated += 1
                    }
                }
            }
        }

        guard totalRated > 0 else {
            return [
                EffortHistogramBin(rir: 0, label: "RIR 0", count: 0, percentage: 0, isHard: false),
                EffortHistogramBin(rir: 1, label: "RIR 1", count: 0, percentage: 0, isHard: true),
                EffortHistogramBin(rir: 2, label: "RIR 2", count: 0, percentage: 0, isHard: true),
                EffortHistogramBin(rir: 3, label: "RIR 3", count: 0, percentage: 0, isHard: true),
                EffortHistogramBin(rir: 4, label: "RIR 4+", count: 0, percentage: 0, isHard: false)
            ]
        }

        return (0...4).map { rir in
            let count = bins[rir] ?? 0
            let pct = Double(count) / Double(totalRated)
            let label = rir == 4 ? "RIR 4+" : "RIR \(rir)"
            let isHard = rir >= 1 && rir <= 3
            return EffortHistogramBin(rir: rir, label: label, count: count, percentage: pct, isHard: isHard)
        }
    }

    public static func computeExercisePerformances(
        exerciseID: String,
        sessions: [CompletedSessionSnapshot],
        limit: Int = 5
    ) -> [ExerciseLoggedPerformance] {
        var performances: [ExerciseLoggedPerformance] = []

        for session in sessions.sorted(by: { $0.date > $1.date }) {
            for entry in session.entries where entry.exerciseID == exerciseID && entry.countsTowardMetrics {
                let workSets = entry.sets.filter(\.isWorkingSet)
                guard !workSets.isEmpty else { continue }

                var topLoad = 0.0
                var topReps = 0
                var bestE1RM = 0.0
                var rirSum = 0.0
                var ratedSets = 0

                var setDescriptions: [String] = []

                for set in workSets {
                    let load = set.actualLoadKg
                    let reps = set.actualReps
                    if load > topLoad || (load == topLoad && reps > topReps) {
                        topLoad = load
                        topReps = reps
                    }
                    let e1 = Estimated1RM.epley(loadKg: load, reps: reps)
                    if e1 > bestE1RM {
                        bestE1RM = e1
                    }

                    if let rpe = set.rpe {
                        let rir = (10.0 - rpe)
                        let rirStr = rir == Double(Int(rir)) ? "\(Int(rir))" : String(format: "%.1f", rir)
                        setDescriptions.append("\(load == Double(Int(load)) ? "\(Int(load))" : String(format: "%.1f", load))×\(reps) (RIR \(rirStr))")
                        rirSum += rir
                        ratedSets += 1
                    } else {
                        setDescriptions.append("\(load == Double(Int(load)) ? "\(Int(load))" : String(format: "%.1f", load))×\(reps)")
                    }
                }

                let avgRIR = ratedSets > 0 ? (rirSum / Double(ratedSets)) : nil

                performances.append(
                    ExerciseLoggedPerformance(
                        date: session.date,
                        topSetWeightKg: topLoad,
                        topSetReps: topReps,
                        estimated1RM: bestE1RM,
                        formattedSets: setDescriptions.joined(separator: " "),
                        averageRIR: avgRIR
                    )
                )

                if performances.count >= limit {
                    return performances
                }
            }
        }

        return performances
    }
}
