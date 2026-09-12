//
//  AppDelegate.swift
//  FitnessTracker
//

import UIKit
import UserNotifications

/// Owns the single `NotificationResponder` and installs it as the
/// `UNUserNotificationCenter` delegate in `didFinishLaunchingWithOptions` —
/// early enough to catch a notification tap that cold-launches the app, which
/// a SwiftUI `.task` (runs after first render) would miss.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let notificationResponder = NotificationResponder()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = notificationResponder
        // Must happen before this method returns — BGTaskScheduler asserts
        // on a registration made any later than app launch.
        ProactiveBackgroundScheduler.register()
        return true
    }
}
