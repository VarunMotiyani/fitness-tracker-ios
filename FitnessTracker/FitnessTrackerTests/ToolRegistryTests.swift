import Testing
import Foundation
@testable import FitnessTracker
import Metrics
import FitnessDomain
import LLMKit

@MainActor
@Suite struct ToolRegistryTests {
    @Test func plateMathToolReturnsPlateBreakdown() throws {
        let tool = PlateMathTool()
        let result = tool.run(argsJSON: "{\"targetLoadKg\": 100.0}")
        let data = try #require(result.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["barWeightKg"] as? Double == 20.0)
        let plates = try #require(decoded?["perSidePlatesKg"] as? [Double])
        #expect(plates.reduce(0, +) == 40.0) // (100 - 20) / 2 = 40 per side
    }

    @Test func plateMathToolReturnsErrorForBadArgs() {
        let tool = PlateMathTool()
        #expect(tool.run(argsJSON: "not json").contains("\"error\""))
    }

    @Test func estimateOneRepMaxToolMatchesEpleyFormula() throws {
        let tool = EstimateOneRepMaxTool()
        let result = tool.run(argsJSON: "{\"loadKg\": 100, \"reps\": 5}")
        let data = try #require(result.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let estimate = try #require(decoded?["estimatedOneRepMaxKg"] as? Double)
        #expect(estimate == Estimated1RM.epley(loadKg: 100, reps: 5))
    }

    @Test func getRecoveryStatusToolFiltersBySingleMuscle() throws {
        let statuses: [MuscleGroup: MuscleRecoveryStatus] = [
            .chest: MuscleRecoveryStatus(muscle: .chest, fatigueScore: 0.6, state: .fatigued, retainedStrengthScore: 0.9, lastTrainedDate: nil, daysSinceTrained: nil),
            .back: MuscleRecoveryStatus(muscle: .back, fatigueScore: 0.1, state: .ready, retainedStrengthScore: 1.0, lastTrainedDate: nil, daysSinceTrained: nil),
        ]
        let tool = GetRecoveryStatusTool(statuses: statuses)
        let result = tool.run(argsJSON: "{\"muscle\": \"chest\"}")
        let data = try #require(result.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        #expect(decoded?.count == 1)
        #expect(decoded?.first?["muscle"] as? String == "chest")
    }

    @Test func getRecoveryStatusToolReturnsAllWhenNoMuscleGiven() throws {
        let statuses: [MuscleGroup: MuscleRecoveryStatus] = [
            .chest: MuscleRecoveryStatus(muscle: .chest, fatigueScore: 0.6, state: .fatigued, retainedStrengthScore: 0.9, lastTrainedDate: nil, daysSinceTrained: nil),
            .back: MuscleRecoveryStatus(muscle: .back, fatigueScore: 0.1, state: .ready, retainedStrengthScore: 1.0, lastTrainedDate: nil, daysSinceTrained: nil),
        ]
        let tool = GetRecoveryStatusTool(statuses: statuses)
        let result = tool.run(argsJSON: "{}")
        let data = try #require(result.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        #expect(decoded?.count == 2)
    }

    @Test func getMuscleBalanceToolRanksAndListsMissing() throws {
        let tool = GetMuscleBalanceTool(load: ["chest": 10.0, "biceps": 3.0])
        let result = tool.run(argsJSON: "{}")
        let data = try #require(result.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let worked = try #require(decoded?["worked"] as? [[String: Any]])
        #expect(worked.first?["muscle"] as? String == "chest") // heaviest first
        let notTrained = try #require(decoded?["notTrained"] as? [String])
        #expect(notTrained.contains("hamstring"))
    }

    @Test func queryTrainingDataToolEvaluatesAgainstExport() throws {
        let export = Data("""
        {"workouts": [{"entries": [{"exerciseId": "0025"}]}]}
        """.utf8)
        let tool = QueryTrainingDataTool(exportJSON: export)
        let result = tool.run(argsJSON: "{\"query\": \"workouts[0].entries[0].exerciseId\"}")
        #expect(result.contains("0025"))
    }

    @Test func queryTrainingDataToolReturnsErrorForBadQuery() {
        let tool = QueryTrainingDataTool(exportJSON: Data("{}".utf8))
        let result = tool.run(argsJSON: "{\"query\": \"nope[].field\"}")
        #expect(result.contains("\"error\""))
    }

    @Test func registryExecutesByName() {
        let registry = ToolRegistry(tools: [PlateMathTool()])
        let result = registry.execute(ToolCallRequest(name: "plate_math", argsJSON: "{\"targetLoadKg\": 60}"))
        #expect(!result.contains("\"error\""))
    }

    @Test func registryReturnsErrorJSONForUnknownTool() {
        let registry = ToolRegistry(tools: [])
        let result = registry.execute(ToolCallRequest(name: "nope", argsJSON: "{}"))
        #expect(result.contains("\"error\""))
    }

    @Test func descriptorsListsEveryRegisteredTool() {
        let registry = ToolRegistry(tools: [PlateMathTool(), EstimateOneRepMaxTool()])
        let names = registry.descriptors().map(\.name)
        #expect(names.contains("plate_math"))
        #expect(names.contains("estimate_one_rep_max"))
    }
}
