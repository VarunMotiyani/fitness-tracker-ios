import Foundation
import SwiftUI
import Observation
import AudioToolbox
import UIKit

@MainActor
@Observable
final class WorkoutTimers {
    public struct TimerState: Sendable, Equatable {
        public var isRunning: Bool = false
        public var totalSeconds: Int = 0
        public var remainingSeconds: Int = 0
        public var entryIndex: Int? = nil
        public var startedAt: Date? = nil

        public init(
            isRunning: Bool = false,
            totalSeconds: Int = 0,
            remainingSeconds: Int = 0,
            entryIndex: Int? = nil,
            startedAt: Date? = nil
        ) {
            self.isRunning = isRunning
            self.totalSeconds = totalSeconds
            self.remainingSeconds = remainingSeconds
            self.entryIndex = entryIndex
            self.startedAt = startedAt
        }
    }

    public var rest: TimerState = TimerState()
    public var work: TimerState = TimerState()

    private var tickTimer: Timer?

    public init() {}

    // MARK: - Rest Timer

    public func startRest(seconds: Int, forEntryIndex: Int? = nil) {
        guard seconds > 0 else {
            stopRest()
            return
        }
        stopWork()
        rest = TimerState(
            isRunning: true,
            totalSeconds: seconds,
            remainingSeconds: seconds,
            entryIndex: forEntryIndex,
            startedAt: Date()
        )
        ensureTicker()
    }

    public func addRest(seconds: Int) {
        guard rest.isRunning else { return }
        let newRemaining = rest.remainingSeconds + seconds
        if newRemaining <= 0 {
            stopRest()
        } else {
            rest.remainingSeconds = newRemaining
            rest.totalSeconds = max(rest.totalSeconds, newRemaining)
        }
    }

    public func stopRest() {
        rest = TimerState()
        checkTicker()
    }

    // MARK: - Work Timer (for timed holds / hangs / planks)

    public func startWork(seconds: Int, forEntryIndex: Int? = nil) {
        guard seconds > 0 else {
            stopWork()
            return
        }
        stopRest()
        work = TimerState(
            isRunning: true,
            totalSeconds: seconds,
            remainingSeconds: seconds,
            entryIndex: forEntryIndex,
            startedAt: Date()
        )
        ensureTicker()
    }

    public func stopWork() {
        work = TimerState()
        checkTicker()
    }

    public func shiftOwner(at index: Int, delta: Int) {
        if let current = rest.entryIndex, current == index {
            rest.entryIndex = max(0, current + delta)
        }
        if let current = work.entryIndex, current == index {
            work.entryIndex = max(0, current + delta)
        }
    }

    // MARK: - Timer Ticker

    private func ensureTicker() {
        guard tickTimer == nil else { return }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func checkTicker() {
        if !rest.isRunning && !work.isRunning {
            tickTimer?.invalidate()
            tickTimer = nil
        }
    }

    private func tick() {
        if rest.isRunning {
            if rest.remainingSeconds > 1 {
                rest.remainingSeconds -= 1
                if rest.remainingSeconds <= 3 {
                    AudioServicesPlaySystemSound(1052)
                }
            } else {
                rest.remainingSeconds = 0
                rest.isRunning = false
                AudioServicesPlaySystemSound(1005)
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        }

        if work.isRunning {
            if work.remainingSeconds > 1 {
                work.remainingSeconds -= 1
                if work.remainingSeconds <= 3 {
                    AudioServicesPlaySystemSound(1052)
                }
            } else {
                work.remainingSeconds = 0
                work.isRunning = false
                AudioServicesPlaySystemSound(1005)
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        }

        checkTicker()
    }
}
