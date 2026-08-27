//
//  FitnessTrackerApp.swift
//  FitnessTracker
//
//  Created by Motiyani, Varun on 28/08/26.
//

import SwiftUI
import SwiftData

@main
struct FitnessTrackerApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
            .modelContainer(for: UserProfile.self)   // StoredPlan.self added in the next step
    }
}
