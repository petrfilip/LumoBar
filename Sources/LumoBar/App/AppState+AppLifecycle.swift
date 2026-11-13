import AppKit
import Foundation
import OSLog
import ServiceManagement

extension AppState {
    /// True when the app is registered (including pending user approval).
    var isLaunchAtLoginOn: Bool {
        loginItemStatus == .enabled || loginItemStatus == .requiresApproval
    }

    func refreshLoginItemStatus() {
        loginItemStatus = SMAppService.mainApp.status
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled { try service.register() }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
        } catch {
            showError(L10n.loginItemFailed(enabled: enabled, detail: error.localizedDescription))
        }
        refreshLoginItemStatus()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func quit() {
        removePowerObservers()
        yeelightLiveSync.stopAll()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Reset all settings

    /// Wipes every persisted setting (see `AppResetService`), then relaunches the app.
    ///
    /// Relaunch instead of an in-process reload: state lives in ~15 `@Published`
    /// properties, per-provider clients, the
    /// automation / circadian timers, Yeelight sockets and Sparkle's cached
    /// preferences. Re-initialising all of that in place is easy to get subtly
    /// wrong (a stale timer or secret would survive); a fresh process reads the
    /// now-empty stores and goes through the normal first-launch path
    /// (seeding presets, onboarding) with nothing left to forget.
    func resetAllSettings() {
        isResettingApp = true
        autoSyncTask?.cancel()
        pollResumeTask.cancel()
        yeelightRecovery.cancel()
        focusSceneTask.cancel()
        circadianApplyTask.cancel()
        automationTasks.cancelAll()
        automationScheduler.stop()
        circadianService.stop()
        yeelightLiveSync.stopAll()
        // Registered at login by a previous toggle; the default is off.
        if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
            try? SMAppService.mainApp.unregister()
        }

        let failures = AppResetService().resetAll()
        guard failures.isEmpty else {
            // Nothing was reloaded, so in-memory state is still consistent with
            // what remains on disk; bring the background services back.
            isResettingApp = false
            startAutoSync()
            reconcileYeelightLiveSync()
            automationScheduler.start(with: automations)
            if circadianSettings.isEnabled { circadianService.start(with: circadianSettings) }
            showError(L10n.resetFailed(failures.joined(separator: ", ")))
            return
        }

        relaunchApp()
    }

    /// Starts a fresh instance of this app and quits the current one. The new
    /// instance is forced (`createsNewApplicationInstance`) because LaunchServices
    /// would otherwise just re-activate the running one. If the new instance could
    /// not be started the app keeps running (quitting would leave the user with no
    /// app at all) and tells them to relaunch manually; the data is already wiped
    /// and `isResettingApp` stays set so nothing writes it back.
    private func relaunchApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error {
                    Self.resetLog.error("Relaunch failed after reset: \(error.localizedDescription, privacy: .public)")
                    self?.showError(L10n.resetRelaunchFailed)
                } else {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }
}
