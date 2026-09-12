//
//  FitnessTrackerTests.swift
//  FitnessTrackerTests
//
//  Created by Motiyani, Varun on 28/08/26.
//

import Testing
import Foundation
@testable import FitnessTracker

@MainActor
struct FitnessTrackerTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        // Swift Testing Documentation
        // https://developer.apple.com/documentation/testing
    }

    @Test func tabBarMetricsAreSane() {
        // Liquid Glass floating bar: the Start disc must fit inside the capsule
        // with margin, and touch targets stay comfortably large.
        #expect(TabBarMetrics.startDiameter < TabBarMetrics.capsuleHeight)
        #expect(TabBarMetrics.pillHeight >= 40)
        #expect(TabBarMetrics.iconFontSize >= 17)
        #expect(TabBarMetrics.sideInset > 0)
    }

}
