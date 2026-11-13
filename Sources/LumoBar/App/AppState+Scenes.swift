import AppKit
import Foundation
import OSLog
import ServiceManagement

extension AppState {
    func applyGroupColor() async {
        let targets = lamps.filter { selectedLampIds.contains($0.id) && canShow(groupColor, on: $0) }
        guard !targets.isEmpty else {
            showError(L10n.selectRGBLamp)
            return
        }

        await runBusy {
            let count = try await applyColorToEach(groupColor, on: targets)
            message = L10n.colorApplied(count)
        }
    }

    /// `byUser`: the user picked this scene in the UI, as
    /// opposed to an automation / Focus trigger. A user-picked scene turns
    /// adaptive lighting off, otherwise it would overwrite the scene within
    /// 15 minutes.
    func applyScene(_ preset: LightScenePreset, byUser: Bool = false) async {
        await applyScene(title: preset.title, color: preset.color, byUser: byUser)
    }

    /// Applies a built-in by id ("focus", "relax"...): the user's (possibly
    /// edited) scene when it still exists, else the hard-coded definition, so
    /// automations keep working even if the scene was deleted.
    func applyPreset(id: String, byUser: Bool = false) async {
        if let scene = PresetScenes.scene(forPresetId: id, in: userScenes) {
            await applyScene(scene, byUser: byUser)
        } else if let preset = LightScenePreset.preset(id: id) {
            await applyScene(preset, byUser: byUser)
        }
    }

    func applyScene(_ scene: UserLightScene, byUser: Bool = false) async {
        if let snapshots = scene.snapshots {
            await applyCapture(snapshots: snapshots, name: scene.title, byUser: byUser)
        } else {
            await applyScene(title: scene.title, color: scene.color, byUser: byUser)
        }
    }

    func saveUserScene(id: UUID?, title: String, icon: String, color: HSVColor, snapshots: [LampSnapshot]? = nil) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { showError(L10n.sceneNameRequired); return }
        let cleanIcon = icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "paintpalette.fill" : icon.trimmingCharacters(in: .whitespacesAndNewlines)

        if let id {
            // The scene was deleted while its editor was open: saving must not bring it back.
            guard let index = userScenes.firstIndex(where: { $0.id == id }) else { return }
            userScenes[index].title = cleanTitle
            userScenes[index].icon = cleanIcon
            userScenes[index].color = color
            userScenes[index].snapshots = snapshots
            message = L10n.sceneUpdated(cleanTitle)
        } else {
            userScenes.append(UserLightScene(title: cleanTitle, icon: cleanIcon, color: color, snapshots: snapshots))
            message = L10n.sceneCreated(cleanTitle)
        }
        persistScenes()
    }

    func captureCurrentState() -> [LampSnapshot] {
        lamps.map { lamp in
            LampSnapshot(
                lampId: lamp.id,
                nativeID: lamp.nativeID,
                providerID: lamp.providerID,
                name: lamp.name,
                power: lamp.power,
                brightness: lamp.brightness,
                temperature: lamp.temperature,
                color: lamp.color,
                workMode: lamp.workMode
            )
        }
    }

    private func applyCapture(snapshots: [LampSnapshot], name: String, byUser: Bool) async {
        guard !snapshots.isEmpty else { return }
        let paused = await pauseAdaptiveForScene(byUser: byUser)
        await runBusy(adaptiveNotice: paused) {
            let outcome = await restoreSnapshots(snapshots, on: lamps.filter(\.online))
            for lamp in outcome.updated { updateLamp(lamp) }
            if let error = outcome.firstError { throw error }
            try Task.checkCancellation()
            message = L10n.sceneApplied(name)
        }
    }

    /// How many enabled automations and Focus mappings use `scene` (deleting it switches them off).
    func sceneReferenceCount(_ scene: UserLightScene) -> Int {
        SceneDeletionCleanup.referenceCount(for: scene.id, automations: automations, focusMappings: focusMappings)
    }

    /// Deletes the scene and switches off what pointed at it: an automation or Focus mapping
    /// left aimed at a missing scene would silently do nothing.
    func deleteUserScene(_ scene: UserLightScene) {
        userScenes.removeAll { $0.id == scene.id }
        persistScenes()

        let cleanup = SceneDeletionCleanup.apply(deleting: scene.id, automations: automations, focusMappings: focusMappings)
        if cleanup.automations.map(\.isEnabled) != automations.map(\.isEnabled) {
            automations = cleanup.automations
            persistAutomations()
            automationScheduler.update(automations: automations)
        }
        if cleanup.focusMappings != focusMappings {
            focusMappings = cleanup.focusMappings
            persistFocusMappings()
        }
        message = cleanup.disabledCount > 0 ? L10n.sceneDeletedDisabled : L10n.sceneDeleted
    }

    func applyScene(title: String, color: HSVColor, byUser: Bool) async {
        let selectedTargets = lamps.filter {
            selectedLampIds.contains($0.id) && $0.online && canShow(color, on: $0)
        }
        let targets = selectedTargets.isEmpty
            ? lamps.filter { $0.online && canShow(color, on: $0) }
            : selectedTargets

        guard !targets.isEmpty else {
            showError(L10n.ambianceNoRGB)
            return
        }
        let paused = await pauseAdaptiveForScene(byUser: byUser)

        groupColor = color

        await runBusy(adaptiveNotice: paused) {
            let count = try await applyColorToEach(color, on: targets)
            message = selectedTargets.isEmpty
                ? L10n.ambianceAppliedToAll(title)
                : L10n.ambianceApplied(title, count: count)
        }
    }

    func loadScenes() {
        do {
            userScenes = PresetScenes.relabeled(
                try sceneStore.load(),
                defaultTitles: LightScenePreset.titlesInAllLanguages())
            seedPresetScenesIfNeeded()
        } catch {
            showError(L10n.scenesUnreadable, sticky: true)
        }
    }

    /// Settings › "Restore default scenes": re-adds missing built-ins and
    /// resets modified ones; the user's own scenes are untouched.
    func restoreDefaultScenes() {
        userScenes = PresetScenes.restored(userScenes)
        UserDefaults.standard.set(true, forKey: PresetScenes.seededDefaultsKey)
        persistScenes()
        message = L10n.scenesRestored
    }

    /// One-time migration: the built-in presets become regular scenes in the
    /// user's list. The flag is stored in UserDefaults so a preset the user
    /// later deletes is not seeded again on the next launch; only an explicit
    /// "Restore default scenes" (or a full reset) brings it back. Not run when
    /// scenes.json was unreadable, so a corrupt file is never overwritten.
    private func seedPresetScenesIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: PresetScenes.seededDefaultsKey) else { return }
        userScenes = PresetScenes.seeded(userScenes)
        do {
            try sceneStore.save(userScenes)
            UserDefaults.standard.set(true, forKey: PresetScenes.seededDefaultsKey)
        } catch {
            showError(error)
        }
    }

    private func persistScenes() {
        guard !isResettingApp else { return }
        do {
            try sceneStore.save(userScenes)
        } catch {
            showError(error)
        }
    }
}
