import AppKit
import Foundation
import OSLog
import ServiceManagement

extension AppState {
    // MARK: - Automations

    func saveAutomation(_ automation: Automation) {
        guard !isResettingApp else { return }
        if let idx = automations.firstIndex(where: { $0.id == automation.id }) {
            automations[idx] = automation
        } else {
            automations.append(automation)
        }
        let stored = persistAutomations()
        automationScheduler.update(automations: automations)
        if stored { message = L10n.automationSaved(automation.name) }
    }

    func deleteAutomation(_ automation: Automation) {
        guard !isResettingApp else { return }
        automations.removeAll { $0.id == automation.id }
        let stored = persistAutomations()
        automationScheduler.update(automations: automations)
        if stored { message = L10n.automationDeleted }
    }

    func toggleAutomation(_ automation: Automation) {
        guard !isResettingApp else { return }
        guard let idx = automations.firstIndex(where: { $0.id == automation.id }) else { return }
        automations[idx].isEnabled.toggle()
        persistAutomations()
        automationScheduler.update(automations: automations)
    }

    /// Writes the automations file; on failure the error is shown instead of a "saved" message.
    @discardableResult
    func persistAutomations() -> Bool {
        do {
            try automationStore.save(automations)
            return true
        } catch {
            showError(L10n.automationsSaveFailed(error.localizedDescription))
            return false
        }
    }

    func executeAutomationAction(_ action: AutomationAction) async {
        switch action {
        case .powerOffAll:
            await applyPowerAll(false)
        case .powerOnAll:
            await applyPowerAll(true)
        case .applyScenePreset(let id):
            await applyPreset(id: id)
        case .applyProfile(let id):
            if let scene = userScenes.first(where: { $0.id == id }) {
                await applyScene(scene)
            }
        case .enableAdaptiveLighting:
            await setAdaptiveLighting(enabled: true)
        case .disableAdaptiveLighting:
            await setAdaptiveLighting(enabled: false)
        }
    }

    func startAutomationScheduler() {
        automationScheduler.onFire = { [weak self] automation in
            guard let self else { return }
            var updated = automation
            updated.lastFiredDate = Date()
            if let idx = self.automations.firstIndex(where: { $0.id == automation.id }) {
                self.automations[idx] = updated
            }
            self.automationTasks.replace(automation.id) { [weak self] in
                await self?.executeAutomationAction(automation.action)
            }
        }
        automationScheduler.start(with: automations)
    }

    func loadAutomations() {
        do {
            automations = try automationStore.load()
        } catch {
            showError(L10n.dataReadFailed("automations.json"), sticky: true)
        }
    }
}
