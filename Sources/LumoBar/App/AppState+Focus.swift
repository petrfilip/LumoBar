import AppKit
import Foundation
import OSLog
import ServiceManagement

extension AppState {
    // MARK: - Focus Mode Mappings

    func loadFocusMappings() {
        do {
            focusMappings = try focusMappingStore.loadMappings()
        } catch {
            showError(L10n.dataReadFailed("focusMappings.json"), sticky: true)
        }
    }

    func persistFocusMappings() {
        guard !isResettingApp else { return }
        do {
            try focusMappingStore.saveMappings(focusMappings)
        } catch {
            showError(L10n.focusSaveFailed)
        }
    }

    /// A second mapping for a Focus that already has one updates that one instead (the first
    /// enabled mapping wins in `enabledMapping`, so a duplicate could never take effect).
    func addFocusMapping(_ mapping: FocusMapping) {
        focusMappings = FocusMapping.adding(mapping, to: focusMappings)
        persistFocusMappings()
    }

    func removeFocusMapping(_ id: String) {
        focusMappings.removeAll { $0.id == id }
        persistFocusMappings()
    }

    func updateFocusMapping(_ mapping: FocusMapping) {
        guard focusMappings.contains(where: { $0.id == mapping.id }) else { return }
        focusMappings = FocusMapping.updating(mapping, in: focusMappings)
        persistFocusMappings()
    }

    func sceneForCurrentFocus() -> UserLightScene? {
        guard let currentFocus = currentFocusIdentifier else { return nil }
        guard let mapping = FocusMapping.enabledMapping(for: currentFocus, in: focusMappings) else { return nil }
        guard let sceneId = mapping.sceneId else { return nil }
        return userScenes.first(where: { $0.id == sceneId })
    }

    func applySceneForCurrentFocus() async {
        guard let scene = sceneForCurrentFocus() else { return }
        await applyScene(scene)
    }

    /// Identifiers a `lampcontrol://focus?mode=` URL may activate: the built-in
    /// modes plus whatever the user typed in a mapping.
    var knownFocusIdentifiers: [String] {
        var seen = Set<String>()
        return (availableFocusModes.map(\.identifier) + focusMappings.map(\.focusIdentifier))
            .filter { seen.insert($0.lowercased()).inserted }
    }

    /// Entry point for `lampcontrol://focus?...` URLs (see AppDelegate).
    func handleFocusURL(_ url: URL) {
        // A cold launch via URL can arrive before mappings are loaded.
        guard isFocusAutomationReady else {
            pendingFocusURLs.append(url)
            return
        }

        guard let event = FocusAutomationURL.parse(url) else {
            Self.focusLog.error("Ignoring malformed focus URL: \(url.absoluteString, privacy: .public)")
            return
        }

        switch event {
        case .off:
            currentFocusIdentifier = nil
            // Turning a Focus off must not let a scene that is still being applied finish.
            focusSceneTask.cancel()
        case .activate(let mode):
            guard let known = knownFocusIdentifiers.first(where: { $0.caseInsensitiveCompare(mode) == .orderedSame }) else {
                Self.focusLog.error("Ignoring unknown focus mode: \(mode, privacy: .public)")
                return
            }
            currentFocusIdentifier = known
            // One run at a time: a newer Focus change cancels the previous run (it stops between
            // lamps) and starts only after that has wound down.
            focusSceneTask.replace { [weak self] in await self?.applySceneForCurrentFocus() }
        }
    }

    func finishFocusAutomationSetup() {
        isFocusAutomationReady = true
        let pending = pendingFocusURLs
        pendingFocusURLs = []
        pending.forEach(handleFocusURL)
    }
}
