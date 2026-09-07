import Foundation
import Metrics
import FitnessDomain
import LLMKit

struct GetRecoveryStatusArgs: Decodable { let muscle: String? }

/// Live per-muscle fatigue/retained-strength — not something the model could
/// reason out itself, since it depends on actual logged-set timestamps only
/// the app's database has. `statuses` is precomputed once per finalize call
/// (via `RecoveryModel.computeRecovery`) and captured here, not recomputed
/// per tool invocation — this tool never touches `ModelContext` itself.
@MainActor
struct GetRecoveryStatusTool: CoachTool {
    let statuses: [MuscleGroup: MuscleRecoveryStatus]

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            name: "get_recovery_status",
            description: "Live per-muscle fatigue/retained-strength. Omit 'muscle' for all muscles.",
            argsSchemaJSON: "{\"muscle\": \"string?, one of the MuscleGroup raw values (chest, back, lowerBack, traps, shoulders, biceps, triceps, forearms, quads, hamstrings, glutes, calves, abs)\"}"
        )
    }

    func run(argsJSON: String) -> String {
        let args = decodeArgs(argsJSON, as: GetRecoveryStatusArgs.self)
        let filtered: [MuscleGroup: MuscleRecoveryStatus]
        if let raw = args?.muscle, let muscle = MuscleGroup(rawValue: raw) {
            filtered = statuses[muscle].map { [muscle: $0] } ?? [:]
        } else {
            filtered = statuses
        }
        let payload = filtered.map { muscle, status in
            [
                "muscle": muscle.rawValue,
                "fatigueScore": status.fatigueScore,
                "state": status.state.rawValue,
                "retainedStrengthScore": status.retainedStrengthScore,
                "daysSinceTrained": status.daysSinceTrained ?? NSNull()
            ] as [String: Any]
        }
        return encodeArrayOfObjects(payload)
    }
}

struct GetMuscleBalanceArgs: Decodable { let windowDays: Int? }

/// Live effective-set volume per muscle over a rolling window — wraps
/// `MuscleBalanceModel`, the same model Stats' muscle-balance card already
/// uses, so the coach's read of "what's undertrained" can't disagree with
/// what's on screen.
@MainActor
struct GetMuscleBalanceTool: CoachTool {
    /// Effective-set load already computed (`MuscleBalanceModel.loadOf`) for
    /// the caller's chosen window — this tool only formats and ranks it.
    let load: [String: Double]

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            name: "get_muscle_balance",
            description: "Effective-set volume per muscle for the current window, ranked heaviest-first, plus which known muscles have none.",
            argsSchemaJSON: "{}"
        )
    }

    func run(argsJSON: String) -> String {
        let (worked, missed) = MuscleBalanceModel.rankOf(load: load)
        let workedPayload = worked.map { slug in
            ["muscle": slug, "effectiveSets": load[slug] ?? 0] as [String: Any]
        }
        return encodeJSONObject(["worked": workedPayload, "notTrained": missed])
    }
}

private func encodeArrayOfObjects(_ array: [[String: Any]]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: array),
          let str = String(data: data, encoding: .utf8)
    else { return "{\"error\": \"failed to encode\"}" }
    return str
}
