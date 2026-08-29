public enum OutcomeSignal: Sendable, Equatable {
    case improved
    case unchanged
    case worse
}

public enum MemoryOutcome {
    public static func applyResult(
        to memory: CoachMemory,
        signal: OutcomeSignal,
        weight: Double = 0.3
    ) -> CoachMemory {
        let delta: Double = signal == .improved ? 1.0 : (signal == .worse ? -1.0 : 0.0)
        let raw = (memory.outcomeScore ?? 0) * (1 - weight) + delta * weight
        let new = min(1, max(-1, raw))

        var result = memory
        result.outcomeScore = new
        return result
    }
}
