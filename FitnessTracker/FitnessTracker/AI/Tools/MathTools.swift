import Foundation
import LLMKit
import Metrics

struct PlateMathArgs: Decodable { let targetLoadKg: Double }

/// Plates per side for a target total load, standard 20kg Olympic bar —
/// exists so the coach's number matches the same "Plates" button already in
/// the workout runner (`PlateMathSheet`) exactly, rather than risk the model
/// computing its own, possibly different, breakdown.
struct PlateMathTool: CoachTool {
    var descriptor: ToolDescriptor {
        ToolDescriptor(
            name: "plate_math",
            description: "Plates to load per side for a target total load, standard 20kg Olympic bar. Use this instead of doing the arithmetic yourself.",
            argsSchemaJSON: "{\"targetLoadKg\": \"number\"}"
        )
    }

    func run(argsJSON: String) -> String {
        guard let args = decodeArgs(argsJSON, as: PlateMathArgs.self) else {
            return "{\"error\": \"bad args\"}"
        }
        let perSide = max(0, (args.targetLoadKg - 20.0) / 2.0)
        let available: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]
        var remaining = perSide
        var plates: [Double] = []
        for plate in available {
            while remaining >= plate - 0.01 {
                plates.append(plate)
                remaining -= plate
            }
        }
        return encodeJSONObject(["barWeightKg": 20.0, "perSidePlatesKg": plates, "totalLoadKg": args.targetLoadKg])
    }
}

struct EstimateOneRepMaxArgs: Decodable { let loadKg: Double; let reps: Int }

/// Wraps `Estimated1RM.epley` — the same formula Stats' "Best: X kg" already
/// uses — so the coach's 1RM estimate can never disagree with what's on
/// screen elsewhere in the app.
struct EstimateOneRepMaxTool: CoachTool {
    var descriptor: ToolDescriptor {
        ToolDescriptor(
            name: "estimate_one_rep_max",
            description: "Epley-formula estimated 1RM for a logged set. Use this instead of estimating it yourself.",
            argsSchemaJSON: "{\"loadKg\": \"number\", \"reps\": \"integer\"}"
        )
    }

    func run(argsJSON: String) -> String {
        guard let args = decodeArgs(argsJSON, as: EstimateOneRepMaxArgs.self) else {
            return "{\"error\": \"bad args\"}"
        }
        let estimate = Estimated1RM.epley(loadKg: args.loadKg, reps: args.reps)
        return encodeJSONObject(["estimatedOneRepMaxKg": estimate])
    }
}
