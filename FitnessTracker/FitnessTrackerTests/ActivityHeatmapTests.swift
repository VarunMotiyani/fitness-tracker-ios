import Foundation
import Testing
import FitnessDomain
import ExerciseCatalog
@testable import FitnessTracker

@MainActor
struct ActivityHeatmapTests {
    @Test func dayActivityItemHasTimestampIdentifier() {
        let now = Date()
        let item = DayActivityItem(date: now)
        #expect(item.id == now.timeIntervalSince1970)
        #expect(item.date == now)
    }

    @Test func heatmapInstantiatesAndHandlesCallback() {
        var tappedDate: Date? = nil
        let testDate = Date()
        let view = ActivityHeatmapView(
            activityDays: [testDate: (count: 2, volume: 5000)],
            onDay: { date in
                tappedDate = date
            }
        )

        #expect(view.onDay != nil)
        view.onDay?(testDate)
        #expect(tappedDate == testDate)
    }
}

