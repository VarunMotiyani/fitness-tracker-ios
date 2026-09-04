import Testing
import Foundation
@testable import Metrics

@Suite struct PulseQueryTests {
    let sampleJSON = Data("""
    {
      "sessions": [
        {
          "startedAt": "2026-08-01T10:00:00Z",
          "entries": [
            { "exerciseID": "0025", "sets": [
              { "actualLoadKg": 60.0, "actualReps": 8 },
              { "actualLoadKg": 62.5, "actualReps": 6 }
            ]},
            { "exerciseID": "0043", "sets": [
              { "actualLoadKg": 40.0, "actualReps": 10 }
            ]}
          ]
        },
        {
          "startedAt": "2026-08-08T10:00:00Z",
          "entries": [
            { "exerciseID": "0025", "sets": [
              { "actualLoadKg": 65.0, "actualReps": 5 }
            ]}
          ]
        }
      ]
    }
    """.utf8)

    @Test func dotPathNavigatesObjectsAndArrays() throws {
        let result = try PulseQuery.evaluate("sessions[0].entries[0].exerciseID", against: sampleJSON)
        #expect(result == .string("0025"))
    }

    @Test func wildcardFlattenCollectsAcrossArrays() throws {
        let result = try PulseQuery.evaluate("sessions[].entries[].exerciseID", against: sampleJSON)
        #expect(result == .array([.string("0025"), .string("0043"), .string("0025")]))
    }

    @Test func filterMatchesEquality() throws {
        let result = try PulseQuery.evaluate(
            "sessions[].entries[] | [?exerciseID=='0025']", against: sampleJSON)
        guard case .array(let matches) = result else {
            Issue.record("expected array"); return
        }
        #expect(matches.count == 2)
    }

    @Test func lengthFunctionCountsArrayElements() throws {
        let result = try PulseQuery.evaluate("sessions[] | length(@)", against: sampleJSON)
        #expect(result == .number(2))
    }

    @Test func maxByFindsHighestField() throws {
        let result = try PulseQuery.evaluate(
            "sessions[].entries[].sets[] | max_by(@, &actualLoadKg)", against: sampleJSON)
        guard case .object(let set) = result else {
            Issue.record("expected object"); return
        }
        #expect(set["actualLoadKg"] == .number(65.0))
    }

    @Test func unknownPathThrowsEvaluationError() {
        #expect(throws: PulseQueryError.self) {
            try PulseQuery.evaluate("sessions[].nope", against: sampleJSON)
        }
    }

    @Test func malformedJSONThrowsParseError() {
        #expect(throws: PulseQueryError.self) {
            try PulseQuery.evaluate("sessions", against: Data("{not json".utf8))
        }
    }
}
