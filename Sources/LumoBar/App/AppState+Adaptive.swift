import AppKit
import Foundation
import OSLog
import ServiceManagement

extension AppState {
    // MARK: - Adaptive Lighting

    /// Turns adaptive lighting off before a user-picked scene. Returns true when it was on, so
    /// the caller can have its own confirmation message say so (`runBusy(adaptiveNotice:)`).
    func pauseAdaptiveForScene(byUser: Bool) async -> Bool {
        guard byUser, circadianSettings.isEnabled else { return false }
        await setAdaptiveLighting(enabled: false)
        return true
    }

    func setAdaptiveLighting(enabled: Bool) async {
        guard !isResettingApp else { return }
        circadianSettings.isEnabled = enabled
        do {
            _ = try circadianSettingsStore.save(circadianSettings)
        } catch {
            showError(L10n.adaptiveSaveFailed(error.localizedDescription))
        }
        if enabled {
            circadianService.start(with: circadianSettings)
        } else {
            circadianService.stop()
        }
    }

    func saveCircadianSettings(_ settings: CircadianSettings) async {
        await runBusy {
            guard !isResettingApp else { return }
            circadianSettings = try circadianSettingsStore.save(settings)
            circadianService.start(with: circadianSettings)
            message = L10n.adaptiveSaved
        }
    }

    func applyCircadianNow() async {
        guard circadianSettings.isEnabled, !isResettingApp else { return }
        // Before the first sync `lamps` is empty and there is nothing to adjust: apply right
        // after that sync instead of waiting for the next 15-minute tick.
        guard hasSyncedOnce else {
            circadianApplyPending = true
            return
        }
        let (brightness, temperature) = circadianService.currentValues()
        // Only adjust lamps that are already on: adaptive lighting must not
        // switch lamps on, and bulbs reject CT/brightness while off anyway.
        let targets = lamps.filter { $0.online && $0.power }
        guard !targets.isEmpty else { return }
        // Runs every 15 min in the background: no busy state and no banner,
        // which used to dim the UI and resize the popover on every tick.
        for lamp in targets {
            guard !Task.isCancelled else { return }
            // A lamp the user is adjusting belongs to them; the next tick catches up.
            guard !isHolding(lamp.id), let provider = try? makeLightProvider(for: lamp) else { continue }
            // Providers take each lamp's native range: convert from % / Kelvin.
            if circadianSettings.applyBrightness, let capability = lamp.capabilities.brightness,
               let updated = try? await provider.setBrightness(
                   deviceId: lamp.nativeID,
                   value: LampScale.nativeBrightness(percent: brightness, capability: capability)),
               !isHolding(lamp.id) {
                updateLamp(updated)
            }
            if circadianSettings.applyTemperature, let capability = lamp.capabilities.temperature,
               !isHolding(lamp.id),
               let updated = try? await provider.setTemperature(
                   deviceId: lamp.nativeID,
                   value: LampScale.nativeTemperature(kelvin: temperature, capability: capability)),
               !isHolding(lamp.id) {
                updateLamp(updated)
            }
        }
    }

    func scheduleCircadianApply() {
        circadianApplyTask.replace { [weak self] in await self?.applyCircadianNow() }
    }

    func startCircadianService() {
        circadianService.onApply = { [weak self] _, _ in
            self?.scheduleCircadianApply()
        }
        if circadianSettings.isEnabled {
            circadianService.start(with: circadianSettings)
        }
    }

    func loadCircadianSettings() {
        do {
            circadianSettings = try circadianSettingsStore.load()
        } catch {
            showError(L10n.dataReadFailed("circadian-settings.json"), sticky: true)
        }
    }
}
