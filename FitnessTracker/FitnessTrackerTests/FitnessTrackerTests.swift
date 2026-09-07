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

    @Test func tabBarUsesSharedIconMetrics() {
        #expect(TabBarMetrics.iconFrame == CGSize(width: 28, height: 24))
        #expect(TabBarMetrics.iconContentFrame == CGSize(width: 22, height: 22))
        #expect(TabBarMetrics.iconFontSize == 20)
        #expect(TabBarMetrics.titleFontSize == 10)
        #expect(TabBarMetrics.centerActionOverlayWidth == 80)
        #expect(TabBarMetrics.primaryTabCount == 5)
    }

}
