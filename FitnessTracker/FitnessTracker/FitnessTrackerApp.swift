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
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup { RootView() }
            .environmentObject(appDelegate.notificationResponder)
            .modelContainer(for: AppSchema.models)
    }
}
