import AppKit
import Foundation
import OSLog
import ServiceManagement

extension AppState {
    /// The one place that orders launch: settings and data load first, then the first sync, and
    /// only then the services that act on that data (auto-sync, Yeelight listeners, the
    /// automation scheduler, adaptive lighting). `AppDelegate` starts none of them itself.
    func runStartupSequence() async {
        await loadSettings()
        loadHueSettings()
        loadLifxSettings()
        loadGoveeSettings()
        loadYeelightSettings()
        loadNanoleafSettings()
        loadWizSettings()
        loadAutomations()
        loadCircadianSettings()
        reportDataRecoveries()
        // Only now do all providers' settings exist, so "nothing configured" is meaningful.
        presentOnboardingIfNeeded()
        await syncLamps(silent: true)
        // Load rooms after initial sync and ensure default migration
        await loadRoomsAndMigrateIfNeeded()
        loadFocusMappings()
        reportDataRecoveries()
        startAutoSync()
        finishFocusAutomationSetup()
        reconcileYeelightLiveSync()
        startAutomationScheduler()
        startCircadianService()
    }

    /// "Configure": opens the providers list. Counts as dismissing, the user has acted on it.
    func openOnboardingProviders() {
        dismissOnboarding()
        requestedSettingsPage = .providers
        selectedTab = .settings
    }

    /// Explicit dismissal (X, Escape, "Configure"): not shown again.
    func dismissOnboarding() {
        UserDefaults.standard.set(true, forKey: onboardingDismissedKey)
        isOnboardingPresented = false
    }

    /// Tap outside the card: just closes it; it comes back on the next launch.
    func closeOnboardingTemporarily() {
        isOnboardingPresented = false
    }

    func openConfigurationGuide() {
        guard let url = URL(string: "https://github.com/petrfilip/LumoBar/blob/main/docs/CONFIGURATION.md") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Tells the user, once, about files the stores had to set aside while loading (see
    /// `JSONFileStore` for the policy).
    private func reportDataRecoveries() {
        let events = RecoveryLog.shared.drain()
        guard !events.isEmpty else { return }
        showError(L10n.dataRecovered(events), sticky: true)
    }

    private func presentOnboardingIfNeeded() {
        isOnboardingPresented = OnboardingPolicy.shouldPresent(
            hasConfiguredProvider: canSync,
            dismissed: UserDefaults.standard.bool(forKey: onboardingDismissedKey))
    }
}
