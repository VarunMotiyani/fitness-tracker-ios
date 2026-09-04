import FitnessDomain
import Metrics

// `CoachSource` (.ai / .rule) already exists in `Metrics/MetricSnapshots.swift`,
// backing `CompletedSessionModel.coachSourceRaw` — reused here rather than a
// second, duplicate enum.

struct FinalizedResult: Sendable {
    let session: FinalizedSession
    let coachSource: CoachSource
}

@MainActor
protocol SessionFinalizing {
    func finalize(_ planned: PlannedSession, energy: EnergyRating, timeAvailableMin: Int) async -> FinalizedResult
}

extension RuleEngineFinalizer: SessionFinalizing {
    func finalize(_ planned: PlannedSession, energy: EnergyRating, timeAvailableMin: Int) async -> FinalizedResult {
        FinalizedResult(session: finalize(planned, energy: energy, timeAvailableMin: timeAvailableMin), coachSource: .rule)
    }
}
