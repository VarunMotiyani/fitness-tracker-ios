import Testing
import Foundation
import SwiftData
@testable import FitnessTracker

@Suite struct PendingCoachSuggestionTests {
    @Test func defaultsAndRoundTrips() throws {
        let container = try ModelContainer(for: PendingCoachSuggestion.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let s = PendingCoachSuggestion(plannedSessionID: UUID(), kind: "exerciseSwap",
                                       exerciseID: "bench", rationale: "test", source: "askCoach")
        ctx.insert(s)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<PendingCoachSuggestion>())
        #expect(fetched.count == 1)
        #expect(fetched[0].resolvedAt == nil)
        #expect(fetched[0].accepted == nil)
    }
}
