import Foundation

/// Per-view memo for `StatsView`'s derived analytics. Each entry recomputes
/// only when its declared dependencies change (the snapshot generation plus
/// whatever window/filter knobs it reads), instead of on every `body` pass.
@MainActor
final class StatsAnalyticsCache {
    private var keys: [String: Int] = [:]
    private var values: [String: Any] = [:]

    func value<T>(_ name: String, deps: [AnyHashable], _ build: () -> T) -> T {
        var hasher = Hasher()
        for dep in deps { hasher.combine(dep) }
        let key = hasher.finalize()
        if keys[name] == key, let cached = values[name] as? T {
            return cached
        }
        let fresh = build()
        keys[name] = key
        values[name] = fresh
        return fresh
    }
}
