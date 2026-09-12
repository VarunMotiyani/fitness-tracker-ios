import Foundation
import BackgroundTasks
import SwiftData
import LLMKit
import os

/// The one real "runs without the app being open" trigger this app has.
/// `ProactiveCoordinator.runDueChecks()` otherwise only fires on
/// `scenePhase == .active` — opening the app. This drives the same call from
/// `BGTaskScheduler`, iOS's background-execution API: opportunistic, not
/// exact. iOS decides *if and when* to actually grant the task a few seconds
/// of runtime — typically while the device is idle/charging, sometime after
/// `earliestBeginDate` — not "at 7am sharp." A user who force-quits the app
/// (swipes it away in the app switcher) disables this until they next open
/// it manually; that's an iOS platform rule, not something this code can
/// work around. See docs/13 §11.
@MainActor
enum ProactiveBackgroundScheduler {
    static let taskIdentifier = "com.varunmotiyani.FitnessTracker.proactiveRefresh"
    private static let log = Logger(subsystem: "com.varunmotiyani.TrainSage", category: "ProactiveBackground")

    /// Must run before `application(_:didFinishLaunchingWithOptions:)`
    /// returns — `BGTaskScheduler` asserts if registration happens later.
    static func register() {
        // `using: nil` runs the callback on an internal background queue —
        // but `handle`/`ProactiveCoordinator` are @MainActor, so that crashed
        // with `_dispatch_assert_queue_fail` the moment the OS actually
        // invoked it (caught live on-device: an EXC_BREAKPOINT in
        // dispatch_assert_queue_fail the instant the simulated task fired).
        // Passing `.main` here is what makes the isolation promise true
        // instead of just declared.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: .main) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    /// Queues the next opportunistic wake-up. A submitted request is consumed
    /// the moment iOS runs it (or gives up on it), so this has to be called
    /// again every time the app leaves the foreground, not just once at
    /// launch — `RootView`'s `.onChange(of: scenePhase)` for `.background` is
    /// the call site. NOT `AppDelegate.applicationDidEnterBackground`: that
    /// never fires in a scene-based app (every default SwiftUI `WindowGroup`
    /// app is one) — UIKit calls scene-phase transitions instead once a
    /// scene exists. Found the hard way via a live device debug session that
    /// showed `submit()` never even being reached.
    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        // A hint, not a promise — iOS won't run it before this, but may well
        // run it hours after. Leaving room lets iOS pick an efficient moment
        // instead of being forced to fire the instant this elapses.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        do {
            try BGTaskScheduler.shared.submit(request)
            log.debug("submitted background refresh request, earliest \(request.earliestBeginDate?.description ?? "nil", privacy: .public)")
        } catch {
            // Swallowed before — surfaced now since a silent failure here
            // means the whole feature is a no-op with nothing to show for it.
            // Common causes: Background App Refresh off (globally or for this
            // app) in iOS Settings, or the simulator (which never actually
            // runs these regardless of submit succeeding).
            log.error("submit failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        // Keep the chain alive regardless of how this run goes — a request
        // is one-shot, so the next one has to be queued unconditionally.
        scheduleNext()

        let work = Task {
            let settings = ProactiveSettingsStore.current()
            guard settings.dailyOn || settings.weeklyOn || settings.patternOn || settings.inbodyOn else {
                task.setTaskCompleted(success: true)
                return
            }
            guard let catalog = try? BundledCatalog.load(),
                  let container = try? ModelContainer(for: Schema(AppSchema.models))
            else {
                task.setTaskCompleted(success: false)
                return
            }

            let context = ModelContext(container)
            let profiles = ((try? context.fetch(FetchDescriptor<ProviderProfile>())) ?? []).filter(\.isActive)
            let provider = profiles.first.flatMap {
                try? LLMProviderFactory.make(from: $0, fallback: $0.resolvedFallback(in: profiles))
            }

            let coordinator = ProactiveCoordinator(
                context: context, catalog: catalog, provider: provider,
                activeProfile: profiles.first, settings: settings)
            await coordinator.runDueChecks()
            task.setTaskCompleted(success: !Task.isCancelled)
        }

        task.expirationHandler = { work.cancel() }
    }
}
