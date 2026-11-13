import AppKit
import Foundation

/// One registered power / session observer, with the center that owns it so it can be removed.
struct PowerObserver {
    let center: NotificationCenter
    let token: NSObjectProtocol
}

extension AppState {
    // MARK: - Pause polling while the Mac sleeps or the session is locked

    /// Waits for several wake / unlock notifications that arrive together, and for the network to
    /// come back, before the catch-up sync.
    private static let resumeDebounce: UInt64 = 1_500_000_000

    /// Pauses the background poll on sleep, display sleep, fast user switching and screen lock,
    /// and resumes it when every one of those has cleared. Manual sync and user commands are not
    /// affected: only the timer-driven poll stops.
    func configurePollingGate() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let events: [(NotificationCenter, Notification.Name, PollingPauseReason, Bool)] = [
            (workspace, NSWorkspace.willSleepNotification, .systemSleep, true),
            (workspace, NSWorkspace.didWakeNotification, .systemSleep, false),
            (workspace, NSWorkspace.screensDidSleepNotification, .displaySleep, true),
            (workspace, NSWorkspace.screensDidWakeNotification, .displaySleep, false),
            (workspace, NSWorkspace.sessionDidResignActiveNotification, .sessionInactive, true),
            (workspace, NSWorkspace.sessionDidBecomeActiveNotification, .sessionInactive, false),
            (distributed, Notification.Name("com.apple.screenIsLocked"), .screenLocked, true),
            (distributed, Notification.Name("com.apple.screenIsUnlocked"), .screenLocked, false)
        ]
        for (center, name, reason, pauses) in events {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if pauses { self?.pausePolling(for: reason) } else { self?.resumePolling(for: reason) }
                }
            }
            powerObservers.append(PowerObserver(center: center, token: token))
        }
    }

    func removePowerObservers() {
        for observer in powerObservers { observer.center.removeObserver(observer.token) }
        powerObservers.removeAll()
    }

    func pausePolling(for reason: PollingPauseReason) {
        guard pollingGate.pause(reason) else { return }
        autoSyncTask?.cancel()
        autoSyncTask = nil
        pollResumeTask.cancel()
    }

    func resumePolling(for reason: PollingPauseReason) {
        guard pollingGate.resume(reason), !isResettingApp else { return }
        // One catch-up sync, then the regular loop. A new resume replaces a pending one.
        pollResumeTask.replace { [weak self] in
            try? await Task.sleep(nanoseconds: Self.resumeDebounce)
            guard let self, !Task.isCancelled, !self.pollingGate.isPaused, !self.isResettingApp else { return }
            await self.syncLamps(silent: true)
            guard !Task.isCancelled, !self.pollingGate.isPaused, !self.isResettingApp else { return }
            self.startAutoSync()
        }
    }
}
