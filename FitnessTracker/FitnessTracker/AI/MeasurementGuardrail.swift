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

    nonisolated private static let units: [String: String] = [
        "bodyweight": "kg",
        "bodyFatPercent": "%",
        "muscleMassKg": "kg"
    ]

    /// The full vocabulary of `kind` strings this guardrail accepts, sorted —
    /// the single source of truth `MemoryKeeperPromptBuilder` builds its
    /// prompt vocabulary from, so the two can't drift apart.
    nonisolated static var knownKinds: [String] {
        bounds.keys.sorted()
    }

    /// The unit a given `kind` is expected to be reported in, or `nil` for an
    /// unrecognized `kind`.
    nonisolated static func expectedUnit(for kind: String) -> String? {
        units[kind]
    }

    nonisolated static func isPlausible(kind: String, value: Double, unit: String) -> Bool {
        guard let range = bounds[kind] else { return false }
        guard unit == expectedUnit(for: kind) else { return false }
        return range.contains(value)
    }
}
