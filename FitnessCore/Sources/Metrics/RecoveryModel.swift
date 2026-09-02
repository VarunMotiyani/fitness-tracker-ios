import Foundation
import FitnessDomain
import ExerciseCatalog

public enum MuscleFatigueState: String, Sendable, Codable, Equatable {
    case ready       // fatigue < 0.25
    case recovering  // 0.25 <= fatigue <= 0.50
    case fatigued    // fatigue > 0.50
    
    public var label: String {
        switch self {
        case .ready: return "Ready"
        case .recovering: return "Recovering"
        case .fatigued: return "Fatigued"
        }
    }
}

public struct MuscleRecoveryStatus: Sendable, Codable, Equatable {
    public let muscle: MuscleGroup
    public let fatigueScore: Double           // [0.0, 1.0]
    public let state: MuscleFatigueState
    public let retainedStrengthScore: Double  // [0.5, 1.0]
    public let lastTrainedDate: Date?
    public let daysSinceTrained: Double?
    
    public init(
        muscle: MuscleGroup,
        fatigueScore: Double,
        state: MuscleFatigueState,
        retainedStrengthScore: Double,
        lastTrainedDate: Date?,
        daysSinceTrained: Double?
    ) {
        self.muscle = muscle
        self.fatigueScore = fatigueScore
        self.state = state
        self.retainedStrengthScore = retainedStrengthScore
        self.lastTrainedDate = lastTrainedDate
        self.daysSinceTrained = daysSinceTrained
    }
}

public enum RecoveryModel {
    /// Reference volume in kg representing a standard hard session stimulus per muscle
    public static let fatigueRefVolume: Double = 2000.0
    
    /// Exponential fatigue half-life in seconds (36 hours)
    public static let fatigueHalfLifeSeconds: TimeInterval = 36 * 3600
    
    /// Full strength retention period in seconds (14 days)
    public static let strengthFullRetentionSeconds: TimeInterval = 14 * 24 * 3600
    
    /// Strength decay half-life in seconds (28 days)
    public static let strengthHalfLifeSeconds: TimeInterval = 28 * 24 * 3600
    
    /// Baseline strength floor for untrained or detrained muscle
    public static let strengthFloor: Double = 0.5
    
    /// Maximum scan window for stimulus calculations (30 days)
    public static let fatigueScanWindowSeconds: TimeInterval = 30 * 24 * 3600
    
    /// Calculate recovery status for all muscle groups given session history and catalog.
    public static func computeRecovery(
        from sessions: [CompletedSessionSnapshot],
        catalog: CatalogStore,
        now: Date = .now
    ) -> [MuscleGroup: MuscleRecoveryStatus] {
        var lastTrainedDates: [MuscleGroup: Date] = [:]
        var accumulatedFatigue: [MuscleGroup: Double] = [:]
        
        for muscle in MuscleGroup.allCases {
            accumulatedFatigue[muscle] = 0.0
        }
        
        // Sort sessions chronologically
        let sortedSessions = sessions.sorted { $0.date < $1.date }
        let cutoff = now.addingTimeInterval(-fatigueScanWindowSeconds)
        
        for session in sortedSessions {
            guard session.date >= cutoff, session.date <= now else { continue }
            let ageSeconds = now.timeIntervalSince(session.date)
            let decayFraction = pow(0.5, ageSeconds / fatigueHalfLifeSeconds)
            
            // Calculate stimulus per muscle in this session
            let sessionMuscleStimuli = computeSessionStimuli(session: session, catalog: catalog)
            
            for (muscle, stimulus) in sessionMuscleStimuli {
                if stimulus > 0 {
                    // Update last trained date if this session is more recent
                    if let prevDate = lastTrainedDates[muscle] {
                        if session.date > prevDate {
                            lastTrainedDates[muscle] = session.date
                        }
                    } else {
                        lastTrainedDates[muscle] = session.date
                    }
                    
                    // Saturation curve: 1 - exp(-stimulus / REF)
                    let saturatedStimulus = 1.0 - exp(-stimulus / fatigueRefVolume)
                    let decayedFatigue = saturatedStimulus * decayFraction
                    accumulatedFatigue[muscle, default: 0.0] += decayedFatigue
                }
            }
        }
        
        // Build result dictionary
        var result: [MuscleGroup: MuscleRecoveryStatus] = [:]
        for muscle in MuscleGroup.allCases {
            let fatigue = min(1.0, accumulatedFatigue[muscle] ?? 0.0)
            let state: MuscleFatigueState
            if fatigue < 0.25 {
                state = .ready
            } else if fatigue <= 0.50 {
                state = .recovering
            } else {
                state = .fatigued
            }
            
            let lastDate = lastTrainedDates[muscle]
            let daysSince: Double? = lastDate.map { now.timeIntervalSince($0) / (24 * 3600) }
            
            let retainedStrength: Double
            if let lastDate = lastDate {
                let age = now.timeIntervalSince(lastDate)
                if age <= strengthFullRetentionSeconds {
                    retainedStrength = 1.0
                } else {
                    let decayAge = age - strengthFullRetentionSeconds
                    let decay = pow(0.5, decayAge / strengthHalfLifeSeconds)
                    retainedStrength = max(strengthFloor, strengthFloor + (1.0 - strengthFloor) * decay)
                }
            } else {
                retainedStrength = strengthFloor
            }
            
            result[muscle] = MuscleRecoveryStatus(
                muscle: muscle,
                fatigueScore: (fatigue * 100).rounded() / 100,
                state: state,
                retainedStrengthScore: (retainedStrength * 100).rounded() / 100,
                lastTrainedDate: lastDate,
                daysSinceTrained: daysSince.map { ($0 * 10).rounded() / 10 }
            )
        }
        
        return result
    }
    
    private static func computeSessionStimuli(
        session: CompletedSessionSnapshot,
        catalog: CatalogStore
    ) -> [MuscleGroup: Double] {
        var stimuli: [MuscleGroup: Double] = [:]
        
        for entry in session.entries where entry.countsTowardMetrics {
            let exercise = catalog.exercise(id: entry.exerciseID)
            let primary = exercise?.primaryMuscle
            let secondaries = exercise?.secondaryMuscles ?? []
            
            // Compute 1RM for this exercise in the session
            var sessionMax1RM: Double = 0.0
            for set in entry.sets where set.isWorkingSet {
                let e1rm = Estimated1RM.epley(loadKg: set.actualLoadKg, reps: set.actualReps)
                if e1rm > sessionMax1RM {
                    sessionMax1RM = e1rm
                }
            }
            
            for set in entry.sets where set.isWorkingSet {
                let rawTonnage = set.actualLoadKg * Double(set.actualReps)
                let weightedTonnage: Double
                if sessionMax1RM > 0 && set.actualLoadKg > 0 {
                    let ratio = min(1.0, set.actualLoadKg / sessionMax1RM)
                    weightedTonnage = rawTonnage * pow(ratio, 1.5)
                } else {
                    weightedTonnage = rawTonnage > 0 ? rawTonnage : (fatigueRefVolume / 3.0)
                }
                
                if let primary = primary {
                    stimuli[primary, default: 0.0] += weightedTonnage
                }
                for sec in secondaries {
                    stimuli[sec, default: 0.0] += weightedTonnage * 0.5
                }
            }
        }
        
        return stimuli
    }
}
