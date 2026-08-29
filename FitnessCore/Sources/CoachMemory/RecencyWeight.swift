import Foundation

/// Exponential recency decay shared by memory ranking and cap eviction so there
/// is a single decay definition. Returns `1.0` at `lastConfirmedAt` and halves
/// every `halfLifeDays`; never negative, clamped at age 0 for future timestamps.
func recencyWeight(_ lastConfirmedAt: Date, now: Date, halfLifeDays: Double = 30) -> Double {
    let ageDays = max(0, now.timeIntervalSince(lastConfirmedAt) / 86_400)
    return pow(0.5, ageDays / halfLifeDays)
}
