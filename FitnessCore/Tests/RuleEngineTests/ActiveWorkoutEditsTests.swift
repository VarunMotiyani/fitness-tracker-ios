import Testing
import Foundation
@testable import RuleEngine

struct ActiveWorkoutEditsTests {
    @Test func moveUnitKeepsSupersetsContiguous() {
        var entries = [
            RunnerEntry(id: "1", supersetID: "A"),
            RunnerEntry(id: "2", supersetID: "A"),
            RunnerEntry(id: "3", supersetID: nil)
        ]
        #expect(ActiveWorkoutEdits.canMoveUnit(entries: entries, index: 0, direction: 1) == true)
        #expect(ActiveWorkoutEdits.canMoveUnit(entries: entries, index: 0, direction: -1) == false)

        let result = ActiveWorkoutEdits.moveUnit(entries: &entries, index: 0, direction: 1)
        #expect(result != nil)
        #expect(entries.map(\.id) == ["3", "1", "2"])
        #expect(result?.newCurrent == 1)
    }

    @Test func swapUnloggedReplacesInPlace() {
        var entries = [
            RunnerEntry(id: "1", supersetID: "A", sets: [RunnerSetRow(done: false)]),
            RunnerEntry(id: "2", supersetID: "A", sets: [RunnerSetRow(done: false)])
        ]
        let rep = RunnerEntry(id: "100", sets: [RunnerSetRow(done: false)])
        let res = ActiveWorkoutEdits.swap(entries: &entries, index: 0, replacement: rep)

        #expect(res == .replacedInPlace(index: 0))
        #expect(entries[0].id == "100")
        #expect(entries[0].supersetID == "A") // kept supersetID
    }

    @Test func swapLoggedRequiresConfirmationThenInserts() {
        var entries = [
            RunnerEntry(id: "1", supersetID: "A", sets: [RunnerSetRow(done: true)]),
            RunnerEntry(id: "2", supersetID: "A", sets: [RunnerSetRow(done: false)])
        ]
        let rep = RunnerEntry(id: "100", sets: [RunnerSetRow(done: false)])
        
        // Without confirmation -> needsConfirmation
        let res1 = ActiveWorkoutEdits.swap(entries: &entries, index: 0, replacement: rep, loggedConfirmed: false)
        #expect(res1 == .needsConfirmation(grouped: true, index: 0))

        // With confirmation + keep in group -> inserted at index + 1
        let res2 = ActiveWorkoutEdits.swap(entries: &entries, index: 0, replacement: rep, loggedConfirmed: true, groupDisposition: .keep)
        #expect(res2 == .inserted(index: 1))
        #expect(entries.map(\.id) == ["1", "100", "2"])
        #expect(entries[1].supersetID == "A")
    }
}
