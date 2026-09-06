import Testing
import SwiftData
import Foundation
@testable import FitnessTracker

@Suite struct ProactiveModelsTests {
    @Test func coachNoteDefaultsUnread() throws {
        let c = try ModelContainer(for: CoachNoteModel.self, WeeklySummaryModel.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(c)
        let note = CoachNoteModel(kindRaw: "daily", text: "Push day today.")
        ctx.insert(note)
        try ctx.save()
        let fetched = try ctx.fetch(FetchDescriptor<CoachNoteModel>())
        #expect(fetched.count == 1)
        #expect(fetched[0].readAt == nil)
    }

    @Test func weeklySummaryRoundTrips() throws {
        let c = try ModelContainer(for: CoachNoteModel.self, WeeklySummaryModel.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(c)
        ctx.insert(WeeklySummaryModel(weekStartDate: Date(), headline: "Solid week",
                                      summaryBody: "4 of 4 sessions.", nextWeekFocus: "Add pulling volume."))
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<WeeklySummaryModel>()).count == 1)
    }
}
