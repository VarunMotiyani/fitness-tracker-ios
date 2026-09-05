import Foundation

/// Plausibility bounds for AI-derived `ObservationModel` writes (design spec
/// §6). An unrecognized `kind` is rejected outright — this call only ever
/// writes a kind the app already knows how to chart, never an invented one.
/// Values passing this check still land with `confirmed = false`; this is
/// "not obviously garbage," not "verified."
enum MeasurementGuardrail {
    nonisolated private static let bounds: [String: ClosedRange<Double>] = [
        "bodyweight": 30...300,
        "bodyFatPercent": 3...60,
        "muscleMassKg": 10...150
    ]

    nonisolated static func isPlausible(kind: String, value: Double) -> Bool {
        guard let range = bounds[kind] else { return false }
        return range.contains(value)
    }
}
