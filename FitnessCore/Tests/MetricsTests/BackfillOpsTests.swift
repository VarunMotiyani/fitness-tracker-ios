import Testing
import Foundation
@testable import Metrics

@Suite struct BackfillOpsTests {
    private func makeSession(id: UUID = UUID(), date: Date) -> CompletedSessionSnapshot {
        CompletedSessionSnapshot(
            id: id, date: date, weekday: 1, timeOfDayMinutes: 600, plannedDurationMin: 60, actualDurationMin: 60,
            energy: .normal, timeAvailableMin: 60, outcome: .complete, partialReason: nil, coachSource: .rule,
            plannedSessionID: nil, entries: [], overallNote: nil, excludeFromProgression: false
        )
    }

    @Test func insertChronologicalPlacesEarlierDateBeforeLater() {
        let now = Date()
        let sToday = makeSession(date: now)
        let sYesterday = makeSession(date: now.addingTimeInterval(-86400))
        let sLastWeek = makeSession(date: now.addingTimeInterval(-86400 * 7))

        let list = BackfillOps.insertChronological([sToday, sYesterday], sLastWeek)
        #expect(list.count == 3)
        #expect(list[0].date == sLastWeek.date)
        #expect(list[1].date == sYesterday.date)
        #expect(list[2].date == sToday.date)
    }

    @Test func commitWithReplaceIDRemovesOldAndInsertsNew() {
        let now = Date()
        let oldID = UUID()
        let sOld = makeSession(id: oldID, date: now.addingTimeInterval(-86400))
        let sToday = makeSession(date: now)
        let sReplacement = makeSession(date: now.addingTimeInterval(-86400))

        let committed = BackfillOps.commit([sOld, sToday], sReplacement, replaceID: oldID)
        #expect(committed.count == 2)
        #expect(!committed.contains(where: { $0.id == oldID }))
        #expect(committed[0].id == sReplacement.id)
    }

    @Test func endInstantAddsDuration() {
        let now = Date()
        let end = BackfillOps.endInstant(start: now, durationMin: 45)
        #expect(end.timeIntervalSince(now) == 45 * 60)
    }
}
