import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var settings = TuyaSettings()
    @Published var hueSettings = HueSettings()
    @Published var lifxSettings = LifxSettings()
    @Published var goveeSettings = GoveeSettings()
    @Published var yeelightSettings = YeelightSettings()
    @Published var nanoleafSettings = NanoleafSettings()
    @Published var wizSettings = WizSettings()
    @Published var shortcutSettings = ShortcutSettings.default
    @Published var automations: [Automation] = []
    @Published var circadianSettings = CircadianSettings.default
    @Published var discoveredHueBridges: [HueBridge] = []
    @Published var lamps: [LampDevice] = []
    @Published var selectedTab: ControlTab = .lamps
    @Published var message = ""
    @Published var isBusy = false
    @Published var hasSecret = false
    @Published var selectedLampIds = Set<String>()
    @Published var groupColor = HSVColor.warm
    @Published var lastSyncDate: Date?
    @Published var isAutoSyncing = false
    @Published var isGroupPanelExpanded = false
    @Published var expandedLampIds = Set<String>()
    @Published var isOnboardingPresented = false
    @Published var userScenes: [UserLightScene] = []
    @Published var licenseState = LicenseState.earlyAccess
    @Published var hideOfflineLamps = false
    @Published var lampOrderIds: [String] = []
    @Published var searchText = ""
    @Published var rooms: [Room] = []
    @Published var focusMappings: [FocusMapping] = []
    @Published var currentFocusIdentifier: String?
    @Published var availableFocusModes: [FocusMode] = [
        FocusMode(identifier: "do-not-disturb", displayName: NSLocalizedString("focus.mode.donotdisturb", comment: "")),
        FocusMode(identifier: "focus", displayName: NSLocalizedString("focus.mode.focus", comment: "")),
        FocusMode(identifier: "sleep", displayName: NSLocalizedString("focus.mode.sleep", comment: ""))
    ]

    @Published var updateService = UpdateService()

    private let settingsStore = SettingsStore()
    private let roomStore = RoomStore()
    private let focusMappingStore = FocusMappingStore()
    private let widgetSnapshotStore = WidgetSnapshotStore()
    private let hueSettingsStore = HueSettingsStore()
    private let lifxSettingsStore = LifxSettingsStore()
    private let goveeSettingsStore = GoveeSettingsStore()
    private let yeelightSettingsStore = YeelightSettingsStore()
    private let nanoleafSettingsStore = NanoleafSettingsStore()
    private let wizSettingsStore = WizSettingsStore()
    private let shortcutSettingsStore = ShortcutSettingsStore()
    private let automationStore = AutomationStore()
    private let circadianSettingsStore = CircadianSettingsStore()
    private let automationScheduler = AutomationScheduler()
    let circadianService = CircadianService()
    private let hueClient = HueClient()
    private let sceneStore = LightSceneStore()
    private let licenseStore = LicenseStore()
    private let licenseActivationService = LicenseActivationService()
    private var lightProviders: [LightProviderKind: any LightProvider] = [:]
    private var autoSyncTask: Task<Void, Never>?
    private let onboardingDismissedKey = "LampControl.onboarding.dismissed"

    init() {
        loadLicense()
        loadScenes()
        lampOrderIds = settingsStore.loadLampOrder()
        Task {
            await loadSettings()
            loadHueSettings()
            loadLifxSettings()
            loadGoveeSettings()
            loadYeelightSettings()
            loadNanoleafSettings()
            loadWizSettings()
            loadShortcutSettings()
            loadAutomations()
            loadCircadianSettings()
            await syncLamps(silent: true)
            // Load rooms after initial sync and ensure default migration
            await loadRoomsAndMigrateIfNeeded()
            loadFocusMappings()
            startAutoSync()
            startFocusMonitoring()
        }
    }

    func loadRoomsAndMigrateIfNeeded() async {
        // Load persisted rooms
        let loaded = roomStore.loadRooms()
        if !loaded.isEmpty {
            rooms = loaded
            return
        }

        // Migration: create an 'Unassigned' room containing all known lamp ids
        let allIds = lamps.map { $0.id }
        let unassigned = Room(name: "Unassigned", lampIds: allIds)
        rooms = [unassigned]
        do {
            try roomStore.saveRooms(rooms)
        } catch {
            message = "Impossible de sauvegarder les pièces."
        }
    }

    func persistRooms() {
        do {
            try roomStore.saveRooms(rooms)
        } catch {
            message = "Impossible de sauvegarder les pièces."
        }
    }

    func lamps(in roomId: String) -> [LampDevice] {
        guard let room = rooms.first(where: { $0.id == roomId }) else { return [] }
        return lamps.filter { room.lampIds.contains($0.id) }
    }

    func roomForLamp(_ lampId: String) -> Room? {
        rooms.first { $0.lampIds.contains(lampId) }
    }

    func assignLamp(_ lampId: String, to roomId: String) {
        // Remove from other rooms
        for i in rooms.indices {
            rooms[i].lampIds.removeAll { $0 == lampId }
        }

        if let idx = rooms.firstIndex(where: { $0.id == roomId }) {
            if !rooms[idx].lampIds.contains(lampId) {
                rooms[idx].lampIds.append(lampId)
            }
        }

        persistRooms()
    }

        func unassignLamp(_ lampId: String) {
            for i in rooms.indices {
                rooms[i].lampIds.removeAll { $0 == lampId }
            }
            persistRooms()
        }

    func setPowerForRoom(_ roomId: String, value: Bool) async {
        guard let room = rooms.first(where: { $0.id == roomId }) else { return }
        let targets = lamps.filter { room.lampIds.contains($0.id) && $0.online }
        guard !targets.isEmpty else { message = "Aucune lampe en ligne dans cette pièce."; return }

        await runBusy {
            var updated: [LampDevice] = []
            for lamp in targets {
                updated.append(try await makeLightProvider(for: lamp).setPower(deviceId: lamp.nativeID, value: value))
            }
            for lamp in updated { updateLamp(lamp) }
            message = value ? "Pièce allumée." : "Pièce éteinte."
        }
    }

    func applyScene(_ scene: UserLightScene, toRoomId roomId: String) async {
        guard licenseState.entitlements.canUseCustomScenes else {
            message = "Les scènes personnalisées sont incluses dans Premium."
            return
        }

        guard let room = rooms.first(where: { $0.id == roomId }) else { return }
        let targets = lamps.filter { room.lampIds.contains($0.id) && $0.online && $0.capabilities.colorCode != nil }
        guard !targets.isEmpty else { message = "Aucune lampe RGB en ligne dans cette pièce."; return }

        await runBusy {
            var updated: [LampDevice] = []
            if let snapshots = scene.snapshots {
                for snap in snapshots {
                    guard let lamp = targets.first(where: { $0.id == snap.lampId }) else { continue }
                    let provider = try makeLightProvider(for: lamp)
                    if let color = snap.color, lamp.capabilities.colorCode != nil {
                        updated.append(try await provider.setColor(deviceId: lamp.nativeID, color: color))
                    } else if let brightness = snap.brightness, lamp.capabilities.brightness != nil {
                        updated.append(try await provider.setBrightness(deviceId: lamp.nativeID, value: brightness))
                    } else if let temp = snap.temperature, lamp.capabilities.temperature != nil {
                        updated.append(try await provider.setTemperature(deviceId: lamp.nativeID, value: temp))
                    }
                }
            } else {
                for lamp in targets {
                    updated.append(try await makeLightProvider(for: lamp).setColor(deviceId: lamp.nativeID, color: scene.color))
                }
            }

            for lamp in updated { updateLamp(lamp) }
            message = "Scène \(scene.title) appliquée à la pièce."
        }
    }

    // MARK: - Focus Mode Mappings

    func loadFocusMappings() {
        focusMappings = focusMappingStore.loadMappings()
    }

    func persistFocusMappings() {
        do {
            try focusMappingStore.saveMappings(focusMappings)
        } catch {
            message = "Impossible de sauvegarder les mappings Focus."
        }
    }

    func addFocusMapping(_ mapping: FocusMapping) {
        focusMappings.append(mapping)
        persistFocusMappings()
    }

    func removeFocusMapping(_ id: String) {
        focusMappings.removeAll { $0.id == id }
        persistFocusMappings()
    }

    func updateFocusMapping(_ mapping: FocusMapping) {
        if let idx = focusMappings.firstIndex(where: { $0.id == mapping.id }) {
            focusMappings[idx] = mapping
            persistFocusMappings()
        }
    }

    func sceneForCurrentFocus() -> UserLightScene? {
        guard let currentFocus = currentFocusIdentifier else { return nil }
        guard let mapping = focusMappings.first(where: { $0.focusIdentifier == currentFocus && $0.isEnabled }) else { return nil }
        guard let sceneId = mapping.sceneId else { return nil }
        return userScenes.first(where: { $0.id == sceneId })
    }

    func applySceneForCurrentFocus() async {
        guard let scene = sceneForCurrentFocus() else { return }
        await applyScene(scene)
    }

    private var focusMonitoringTask: Task<Void, Never>?

    private func startFocusMonitoring() {
        focusMonitoringTask = Task {
            while !Task.isCancelled {
                updateCurrentFocus()
                try? await Task.sleep(nanoseconds: 5_000_000_000) // Check every 5 seconds
            }
        }
    }

    private func updateCurrentFocus() {
        // Placeholder until we wire the real macOS Focus API.
        currentFocusIdentifier = nil
    }

    deinit {
        autoSyncTask?.cancel()
        focusMonitoringTask?.cancel()
    }

    var canSync: Bool {
        canSyncTuya || hueSettings.isConfigured || lifxSettings.isConfigured || goveeSettings.isConfigured || yeelightSettings.isConfigured
    }

    var canSyncTuya: Bool {
        !settings.accessId.isEmpty &&
        !settings.endpoint.isEmpty &&
        !settings.uid.isEmpty &&
        (hasSecret || !settings.accessSecret.isEmpty)
    }

    private var licensedLamps: [LampDevice] {
        guard let maxLamps = licenseState.entitlements.maxLamps else {
            return lamps
        }

        return Array(lamps.prefix(maxLamps))
    }

    var visibleLamps: [LampDevice] {
        var filtered = licensedLamps

        // Filter offline lamps if toggle is on
        if hideOfflineLamps {
            filtered = filtered.filter { $0.online }
        }

        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        // Apply custom ordering
        if !lampOrderIds.isEmpty {
            let orderIndex = Dictionary(uniqueKeysWithValues: lampOrderIds.enumerated().map { ($1, $0) })
            filtered.sort { a, b in
                let aIndex = orderIndex[a.id] ?? Int.max
                let bIndex = orderIndex[b.id] ?? Int.max
                return aIndex < bIndex
            }
        }

        return filtered
    }

    var hiddenLampCount: Int {
        guard let maxLamps = licenseState.entitlements.maxLamps else {
            return 0
        }

        return max(0, lamps.count - maxLamps)
    }

    func updateLampOrder(_ order: [String]) {
        lampOrderIds = order
        settingsStore.saveLampOrder(order)
    }

    var configuredProviderKinds: [LightProviderKind] {
        var providers: [LightProviderKind] = []
        if canSyncTuya { providers.append(.tuya) }
        if hueSettings.isConfigured { providers.append(.philipsHue) }
        if lifxSettings.isConfigured { providers.append(.lifx) }
        if goveeSettings.isConfigured { providers.append(.govee) }
        if yeelightSettings.isConfigured { providers.append(.yeelight) }
        if nanoleafSettings.isConfigured { providers.append(.nanoleaf) }
        if wizSettings.isConfigured { providers.append(.wiz) }
        return providers
    }

    func loadSettings() async {
        do {
            let loaded = try settingsStore.load()
            settings = loaded.settings
            hasSecret = loaded.hasSecret
            presentOnboardingIfNeeded()
        } catch {
            message = error.localizedDescription
        }
    }

    func saveLifxSettingsAndSync() async {
        await runBusy {
            lifxSettings = try lifxSettingsStore.save(lifxSettings)
            lightProviders[.lifx] = nil
            let synced = try await syncConfiguredProviders()
            lamps = synced
            selectedLampIds = selectedLampIds.intersection(Set(synced.map(\.id)))
            expandedLampIds = expandedLampIds.intersection(Set(synced.map(\.id)))
            lastSyncDate = Date()
            message = "LIFX connecté. \(synced.count) lampe(s) synchronisée(s)."
            selectedTab = .lamps
        }
    }

    func saveGoveeSettingsAndSync() async {
        await runBusy {
            goveeSettings = try goveeSettingsStore.save(goveeSettings)
            lightProviders[.govee] = nil
            let synced = try await syncConfiguredProviders()
            lamps = synced
            selectedLampIds = selectedLampIds.intersection(Set(synced.map(\.id)))
            expandedLampIds = expandedLampIds.intersection(Set(synced.map(\.id)))
            lastSyncDate = Date()
            message = "Govee connecté. \(synced.count) lampe(s) synchronisée(s)."
            selectedTab = .lamps
        }
    }

    func addYeelightBulb(host: String, name: String) async {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty else {
            message = "Adresse IP Yeelight requise."
            return
        }

        var (hostOnly, port) = parseYeelightHost(cleanHost)
        if hostOnly.isEmpty { hostOnly = cleanHost; port = 55443 }

        var next = yeelightSettings
        let bulb = YeelightBulb(host: hostOnly, port: port, name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        next.bulbs.append(bulb)

        await runBusy {
            yeelightSettings = try yeelightSettingsStore.save(next)
            lightProviders[.yeelight] = nil
            let synced = try await syncConfiguredProviders()
            lamps = synced
            selectedLampIds = selectedLampIds.intersection(Set(synced.map(\.id)))
            expandedLampIds = expandedLampIds.intersection(Set(synced.map(\.id)))
            lastSyncDate = Date()
            message = "Yeelight ajoutée. \(synced.count) lampe(s) synchronisée(s)."
        }
    }

    func removeYeelightBulb(_ bulb: YeelightBulb) async {
        var next = yeelightSettings
        next.bulbs.removeAll { $0.id == bulb.id }

        await runBusy {
            yeelightSettings = try yeelightSettingsStore.save(next)
            lightProviders[.yeelight] = nil
            let synced = try await syncConfiguredProviders()
            lamps = synced
            selectedLampIds = selectedLampIds.intersection(Set(synced.map(\.id)))
            expandedLampIds = expandedLampIds.intersection(Set(synced.map(\.id)))
            lastSyncDate = Date()
            message = "Yeelight retirée."
        }
    }

    private func parseYeelightHost(_ raw: String) -> (host: String, port: Int) {
        if let colon = raw.lastIndex(of: ":"), let port = Int(raw[raw.index(after: colon)...]) {
            return (String(raw[..<colon]), port)
        }
        return (raw, 55443)
    }

    func saveSettings() async {
        await runBusy {
            let saved = try settingsStore.save(settings)
            settings = saved.settings
            hasSecret = saved.hasSecret
            lightProviders[.tuya] = nil
            message = "Réglages enregistrés."
            selectedTab = .lamps
        }
    }

    func saveSettingsAndSync() async {
        await runBusy {
            let saved = try settingsStore.save(settings)
            settings = saved.settings
            hasSecret = saved.hasSecret
            lightProviders[.tuya] = nil

            let synced = try await syncConfiguredProviders()
            lamps = synced
            selectedLampIds = selectedLampIds.intersection(Set(synced.map(\.id)))
            expandedLampIds = expandedLampIds.intersection(Set(synced.map(\.id)))
            lastSyncDate = Date()
            message = synced.isEmpty ? "Réglages enregistrés. Aucune lampe compatible trouvée." : "\(synced.count) lampe(s) synchronisée(s)."
            selectedTab = .lamps
        }
    }

    func syncLamps(silent: Bool = false) async {
        guard canSync else { return }

        if silent {
            guard !isBusy && !isAutoSyncing else { return }
            isAutoSyncing = true
            defer { isAutoSyncing = false }

            do {
                let synced = try await syncConfiguredProviders()
                lamps = synced
                selectedLampIds = selectedLampIds.intersection(Set(synced.map(\.id)))
                expandedLampIds = expandedLampIds.intersection(Set(synced.map(\.id)))
                lastSyncDate = Date()
                persistWidgetSnapshot()
            } catch {
                // Silent refresh should not interrupt normal use.
            }

            return
        }

        await runBusy {
            let synced = try await syncConfiguredProviders()
            lamps = synced
            selectedLampIds = selectedLampIds.intersection(Set(synced.map(\.id)))
            expandedLampIds = expandedLampIds.intersection(Set(synced.map(\.id)))
            lastSyncDate = Date()
            message = synced.isEmpty ? "Aucune lampe compatible trouvée." : "\(synced.count) lampe(s) synchronisée(s)."
            persistWidgetSnapshot()
        }
    }

    func toggle(_ lamp: LampDevice) async -> Bool {
        updateLamp(lamp.withPower(!lamp.power))

        do {
            let updated = try await makeLightProvider(for: lamp).setPower(deviceId: lamp.nativeID, value: !lamp.power)
            updateLamp(updated)
            return true
        } catch {
            updateLamp(lamp)
            message = error.localizedDescription
            return false
        }
    }

    func previewBrightness(_ lamp: LampDevice, value: Int) {
        updateLamp(lamp.withBrightness(value))
    }

    func commitBrightness(_ lamp: LampDevice, value: Int) async {
        do {
            let updated = try await makeLightProvider(for: lamp).setBrightness(deviceId: lamp.nativeID, value: value)
            updateLamp(updated)
        } catch {
            message = error.localizedDescription
        }
    }

    func previewTemperature(_ lamp: LampDevice, value: Int) {
        updateLamp(lamp.withTemperature(value))
    }

    func commitTemperature(_ lamp: LampDevice, value: Int) async {
        do {
            let updated = try await makeLightProvider(for: lamp).setTemperature(deviceId: lamp.nativeID, value: value)
            updateLamp(updated)
        } catch {
            message = error.localizedDescription
        }
    }

    func previewColor(_ lamp: LampDevice, color: HSVColor) {
        updateLamp(lamp.withColor(color))
    }

    func commitColor(_ lamp: LampDevice, color: HSVColor) async {
        do {
            let updated = try await applyColor(color, to: lamp)
            updateLamp(updated)
        } catch {
            message = error.localizedDescription
        }
    }

    func toggleSelection(_ lamp: LampDevice) {
        guard licenseState.entitlements.canUseGroups else {
            message = "Les groupes sont inclus dans Premium."
            return
        }

        if selectedLampIds.contains(lamp.id) {
            selectedLampIds.remove(lamp.id)
        } else {
            selectedLampIds.insert(lamp.id)
        }

        isGroupPanelExpanded = selectedLampIds.count >= 2
    }

    func selectAllRGBLamps() {
        guard licenseState.entitlements.canUseGroups else {
            message = "Les groupes sont inclus dans Premium."
            return
        }

        selectedLampIds = Set(lamps.filter { $0.online && $0.capabilities.colorCode != nil }.map(\.id))
        isGroupPanelExpanded = selectedLampIds.count >= 2
    }

    func clearSelection() {
        selectedLampIds.removeAll()
        isGroupPanelExpanded = false
    }

    func toggleGroupPanel() {
        isGroupPanelExpanded.toggle()
    }

    func toggleAdvancedControls(for lamp: LampDevice) {
        if expandedLampIds.contains(lamp.id) {
            expandedLampIds.remove(lamp.id)
        } else {
            expandedLampIds.insert(lamp.id)
        }
    }

    func isAdvancedControlsExpanded(for lamp: LampDevice) -> Bool {
        expandedLampIds.contains(lamp.id)
    }

    var preferredPopoverSize: NSSize {
        NSSize(width: 410, height: preferredPopoverHeight)
    }

    private var preferredPopoverHeight: CGFloat {
        let height: CGFloat
        switch selectedTab {
        case .settings: height = 720
        // LampsView wraps its body in a ScrollView; the popover is sized to
        // a content-aware target capped at 620pt. Anything beyond scrolls
        // (rooms, expanded rows, scene editor).
        case .lamps:    height = lampsPopoverHeight
        }
        let screenMax = (NSScreen.main?.visibleFrame.height ?? 900) - 80
        return min(max(height, 360), screenMax)
    }

    private var lampsPopoverHeight: CGFloat {
        // Quiet Glass v2: tab strip removed (gear/back lives in the header).
        // header 56 + outer paddings 28 = ~84pt fixed chrome
        var h: CGFloat = 84

        if !message.isEmpty { h += 56 }

        // status bar card (~56pt)
        h += 56 + 12

        // No providers configured → just show onboarding card.
        if !canSync {
            return min(h + 220, 540)
        }

        // search + offline toggle row
        if !lamps.isEmpty { h += 44 }

        // empty/filter empty state card
        if lamps.isEmpty && !isAutoSyncing { return min(h + 200, 540) }

        if lamps.contains(where: { $0.capabilities.colorCode != nil }) {
            h += 84   // ScenePresetBar
            h += isGroupPanelExpanded || selectedLampIds.count >= 2 ? 220 : 60
        }
        if hiddenLampCount > 0 { h += 56 }

        // Reserve room for ~3 lamp rows + their room headers; ScrollView absorbs the rest.
        let visibleCount = max(1, min(visibleLamps.count, 3))
        h += CGFloat(visibleCount) * 72

        let roomsWithLamps = rooms.filter { room in visibleLamps.contains(where: { room.lampIds.contains($0.id) }) }.count
        h += CGFloat(min(roomsWithLamps, 2)) * 48

        return min(h, 620)
    }

    private func expandedLampRowHeight(for lamp: LampDevice) -> CGFloat {
        var height: CGFloat = 62

        height += 37

        if lamp.capabilities.colorCode != nil || lamp.capabilities.brightness != nil || lamp.capabilities.temperature != nil {
            height += 30
        }

        if lamp.capabilities.temperature != nil {
            height += 30
        }

        if lamp.capabilities.colorCode != nil {
            height += 98
        }

        return height
    }

    func applyGroupColor() async {
        guard licenseState.entitlements.canUseGroups else {
            message = "Les groupes sont inclus dans Premium."
            return
        }

        let targets = lamps.filter { selectedLampIds.contains($0.id) && canShow(groupColor, on: $0) }
        guard !targets.isEmpty else {
            message = "Sélectionnez au moins une lampe RGB."
            return
        }

        await runBusy {
            var updated: [LampDevice] = []
            for lamp in targets {
                updated.append(try await applyColor(groupColor, to: lamp))
            }
            for lamp in updated {
                updateLamp(lamp)
            }
            message = "Couleur appliquée à \(updated.count) lampe(s)."
        }
    }

    func applyScene(_ preset: LightScenePreset) async {
        await applyScene(title: preset.title, color: preset.color)
    }

    func applyScene(_ scene: UserLightScene) async {
        guard licenseState.entitlements.canUseCustomScenes else {
            message = "Les scènes personnalisées sont incluses dans Premium."
            return
        }

        if let snapshots = scene.snapshots {
            await applyCapture(snapshots: snapshots, name: scene.title)
        } else {
            await applyScene(title: scene.title, color: scene.color)
        }
    }

    func saveUserScene(id: UUID?, title: String, icon: String, color: HSVColor, snapshots: [LampSnapshot]? = nil) {
        guard licenseState.entitlements.canUseCustomScenes else {
            message = "Les scènes personnalisées sont incluses dans Premium."
            return
        }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { message = "Nom de scène requis."; return }
        let cleanIcon = icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "paintpalette.fill" : icon.trimmingCharacters(in: .whitespacesAndNewlines)

        if let id, let index = userScenes.firstIndex(where: { $0.id == id }) {
            userScenes[index].title = cleanTitle
            userScenes[index].icon = cleanIcon
            userScenes[index].color = color
            userScenes[index].snapshots = snapshots
            message = "Scène « \(cleanTitle) » mise à jour."
        } else {
            userScenes.append(UserLightScene(title: cleanTitle, icon: cleanIcon, color: color, snapshots: snapshots))
            message = "Scène « \(cleanTitle) » créée."
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

    private func applyCapture(snapshots: [LampSnapshot], name: String) async {
        guard !snapshots.isEmpty else { return }
        await runBusy {
            var updated: [LampDevice] = []
            for snap in snapshots {
                guard let lamp = lamps.first(where: { $0.id == snap.lampId && $0.online }) else { continue }
                let provider = try makeLightProvider(for: lamp)
                if snap.workMode == "white", let temp = snap.temperature, lamp.capabilities.temperature != nil {
                    updated.append(try await provider.setTemperature(deviceId: lamp.nativeID, value: temp))
                    if let brightness = snap.brightness, lamp.capabilities.brightness != nil {
                        updated.append(try await provider.setBrightness(deviceId: lamp.nativeID, value: brightness))
                    }
                } else if let color = snap.color, lamp.capabilities.colorCode != nil {
                    updated.append(try await provider.setColor(deviceId: lamp.nativeID, color: color))
                } else if let brightness = snap.brightness, lamp.capabilities.brightness != nil {
                    updated.append(try await provider.setBrightness(deviceId: lamp.nativeID, value: brightness))
                } else if let temp = snap.temperature, lamp.capabilities.temperature != nil {
                    updated.append(try await provider.setTemperature(deviceId: lamp.nativeID, value: temp))
                }
                if !snap.power {
                    updated.append(try await provider.setPower(deviceId: lamp.nativeID, value: false))
                }
            }
            for lamp in updated { updateLamp(lamp) }
            message = "Scène « \(name) » appliquée."
        }
    }

    func deleteUserScene(_ scene: UserLightScene) {
        guard licenseState.entitlements.canUseCustomScenes else {
            message = "Les scènes personnalisées sont incluses dans Premium."
            return
        }

        userScenes.removeAll { $0.id == scene.id }
        persistScenes()
        persistWidgetSnapshot()
        message = "Scène supprimée."
    }

    private func applyScene(title: String, color: HSVColor) async {
        let selectedTargets = lamps.filter {
            selectedLampIds.contains($0.id) && $0.online && canShow(color, on: $0)
        }
        let targets = selectedTargets.isEmpty
            ? lamps.filter { $0.online && canShow(color, on: $0) }
            : selectedTargets

        guard !targets.isEmpty else {
            message = "Aucune lampe RGB en ligne pour appliquer cette ambiance."
            return
        }

        groupColor = color

        await runBusy {
            var updated: [LampDevice] = []
            for lamp in targets {
                updated.append(try await applyColor(color, to: lamp))
            }
            for lamp in updated {
                updateLamp(lamp)
            }
            let scope = selectedTargets.isEmpty ? "toutes les lampes RGB" : "\(updated.count) lampe(s)"
            message = "Ambiance \(title) appliquée à \(scope)."
        }
    }

    func applyGroupPower(_ value: Bool) async {
        guard licenseState.entitlements.canUseGroups else {
            message = "Les groupes sont inclus dans Premium."
            return
        }

        let targets = lamps.filter { selectedLampIds.contains($0.id) }
        guard !targets.isEmpty else {
            message = "Sélectionnez au moins une lampe."
            return
        }

        await runBusy {
            var updated: [LampDevice] = []
            for lamp in targets {
                updated.append(try await makeLightProvider(for: lamp).setPower(deviceId: lamp.nativeID, value: value))
            }
            for lamp in updated {
                updateLamp(lamp)
            }
            message = value ? "Groupe allumé." : "Groupe éteint."
        }
    }

    func activateLicense(_ licenseKey: String, email: String?) async {
        await runBusy {
            let next = try await licenseActivationService.activate(licenseKey: licenseKey, expectedEmail: email)
            licenseState = next
            try licenseStore.save(next)
            message = "Achat Premium pris en compte."
        }
    }

    func validateLicense() async {
        await runBusy {
            let next = try await licenseActivationService.validate(licenseState)
            licenseState = next
            try licenseStore.save(next)
            message = next.tier == .premium ? "Premium activé." : "Achat Premium non détecté."
        }
    }

    func deactivateLicense() async {
        await runBusy {
            if licenseState.tier == .premium {
                try await licenseActivationService.deactivate(licenseState)
            }

            licenseState = .earlyAccess
            try licenseStore.save(licenseState)
            message = "État local réinitialisé."
        }
    }

    func openPremiumCheckout() {
        Task { await activateLicense("", email: nil) }
    }

    func discoverHueBridges() async {
        await runBusy {
            discoveredHueBridges = try await hueClient.discoverBridges()
            message = discoveredHueBridges.isEmpty ? "Aucun bridge Hue trouvé." : "\(discoveredHueBridges.count) bridge Hue détecté(s)."
        }
    }

    func selectHueBridge(_ bridge: HueBridge) {
        hueSettings.bridgeID = bridge.id
        hueSettings.bridgeIP = bridge.internalipaddress
        message = "Bridge Hue sélectionné. Appuyez sur son bouton, puis connectez."
    }

    func pairHueBridge() async {
        await runBusy {
            let bridgeIP = hueSettings.bridgeIP.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bridgeIP.isEmpty else {
                throw LampControlError.configuration("Sélectionnez ou renseignez un bridge Hue.")
            }

            hueSettings.username = try await hueClient.createUser(bridgeIP: bridgeIP)
            hueSettings = try hueSettingsStore.save(hueSettings)
            lightProviders[.philipsHue] = nil
            message = "Bridge Philips Hue connecté."
        }
    }

    // MARK: - White handling

    /// Whether `color` can be rendered on `lamp`: RGB lamps take any color,
    /// white-only (tunable) lamps take near-white colors via color temperature.
    private func canShow(_ color: HSVColor, on lamp: LampDevice) -> Bool {
        lamp.capabilities.colorCode != nil || (color.isNearWhite && lamp.capabilities.temperature != nil)
    }

    /// Sends `color` to `lamp`. Near-white colors are sent as a neutral color
    /// temperature when the lamp supports it: RGB "white" (saturation 0) looks
    /// dim and bluish on most bulbs, while CT mode uses the dedicated white LEDs.
    private func applyColor(_ color: HSVColor, to lamp: LampDevice) async throws -> LampDevice {
        let provider = try makeLightProvider(for: lamp)
        guard color.isNearWhite, let temperature = lamp.capabilities.temperature else {
            return try await provider.setColor(deviceId: lamp.nativeID, color: color)
        }

        var updated = try await provider.setTemperature(
            deviceId: lamp.nativeID,
            value: Self.neutralWhite(for: temperature)
        )
        if let brightness = lamp.capabilities.brightness {
            let fraction = Double(min(1000, max(10, color.v))) / 1000.0
            let value = brightness.min + Int(round(fraction * Double(brightness.max - brightness.min)))
            updated = try await provider.setBrightness(deviceId: lamp.nativeID, value: value)
        }
        return updated
    }

    /// Neutral white (~4000 K) in the lamp's own temperature scale. Ranges
    /// starting at 1000+ are Kelvin (Yeelight, LIFX, WiZ, Govee); others are
    /// vendor-relative scales where the midpoint is a neutral white.
    private static func neutralWhite(for capability: NumericCapability) -> Int {
        let raw = capability.min >= 1000 ? 4000 : (capability.min + capability.max) / 2
        return min(capability.max, max(capability.min, raw))
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func openOnboardingSettings() {
        isOnboardingPresented = false
        selectedTab = .settings
    }

    func dismissOnboarding() {
        UserDefaults.standard.set(true, forKey: onboardingDismissedKey)
        isOnboardingPresented = false
    }

    func openConfigurationGuide() {
        guard let url = URL(string: "https://github.com/hugoinformatique/LampControl/blob/main/docs/CONFIGURATION.fr.md") else { return }
        NSWorkspace.shared.open(url)
    }

    private func syncConfiguredProviders() async throws -> [LampDevice] {
        let providers = try configuredProviderKinds.map { try makeLightProvider(for: $0) }
        var synced: [LampDevice] = []
        for provider in providers {
            synced.append(contentsOf: try await provider.syncLights())
        }
        return synced.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func makeLightProvider(for lamp: LampDevice) throws -> any LightProvider {
        try makeLightProvider(for: lamp.providerID)
    }

    private func makeLightProvider(for kind: LightProviderKind) throws -> any LightProvider {
        if let provider = lightProviders[kind] {
            return provider
        }

        let provider: any LightProvider
        switch kind {
        case .tuya:
            provider = try makeTuyaProvider()
        case .philipsHue:
            guard hueSettings.isConfigured else {
                throw LampControlError.configuration("Bridge Philips Hue non configuré.")
            }
            provider = HueLightProvider(settings: hueSettings)
        case .lifx:
            guard lifxSettings.isConfigured else {
                throw LampControlError.configuration("Token LIFX manquant.")
            }
            provider = LifxLightProvider(settings: lifxSettings)
        case .govee:
            guard goveeSettings.isConfigured else {
                throw LampControlError.configuration("Clé API Govee manquante.")
            }
            provider = GoveeLightProvider(settings: goveeSettings)
        case .yeelight:
            guard yeelightSettings.isConfigured else {
                throw LampControlError.configuration("Aucune lampe Yeelight enregistrée.")
            }
            provider = YeelightLightProvider(settings: yeelightSettings)
        case .nanoleaf:
            guard nanoleafSettings.isConfigured else {
                throw LampControlError.configuration("Aucun panneau Nanoleaf enregistré.")
            }
            provider = NanoleafLightProvider(settings: nanoleafSettings)
        case .wiz:
            guard wizSettings.isConfigured else {
                throw LampControlError.configuration("Aucune ampoule WiZ enregistrée.")
            }
            provider = WizLightProvider(settings: wizSettings)
        }

        lightProviders[kind] = provider
        return provider
    }

    private func makeTuyaProvider() throws -> TuyaLightProvider {
        let secret = try settingsStore.accessSecret()
        guard !settings.accessId.isEmpty, !secret.isEmpty, !settings.endpoint.isEmpty, !settings.uid.isEmpty else {
            throw LampControlError.configuration("Identifiants Tuya incomplets. Ouvrez les réglages.")
        }

        let client = try TuyaClient(accessId: settings.accessId, accessSecret: secret, endpoint: settings.endpoint)
        let service = TuyaLightProvider(client: client, uid: settings.uid)
        return service
    }

    private func loadHueSettings() {
        do {
            hueSettings = try hueSettingsStore.load()
        } catch {
            message = "Réglages Hue illisibles."
        }
    }

    private func loadLifxSettings() {
        do {
            lifxSettings = try lifxSettingsStore.load()
        } catch {
            message = "Réglages LIFX illisibles."
        }
    }

    private func loadGoveeSettings() {
        do {
            goveeSettings = try goveeSettingsStore.load()
        } catch {
            message = "Réglages Govee illisibles."
        }
    }

    private func loadYeelightSettings() {
        do {
            yeelightSettings = try yeelightSettingsStore.load()
        } catch {
            message = "Réglages Yeelight illisibles."
        }
    }

    // MARK: - Nanoleaf

    func addNanoleafDevice(host: String, name: String) async {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty else { message = "Adresse IP Nanoleaf requise."; return }

        await runBusy {
            let client = NanoleafClient()
            let token = try await client.pairDevice(host: cleanHost)
            let device = NanoleafDevice(name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? cleanHost : name.trimmingCharacters(in: .whitespacesAndNewlines),
                                        host: cleanHost, authToken: token)
            var next = nanoleafSettings
            next.devices.append(device)
            nanoleafSettings = try nanoleafSettingsStore.save(next)
            lightProviders[.nanoleaf] = nil
            let synced = try await syncConfiguredProviders()
            lamps = synced
            selectedLampIds = selectedLampIds.intersection(Set(synced.map(\.id)))
            expandedLampIds = expandedLampIds.intersection(Set(synced.map(\.id)))
            lastSyncDate = Date()
            message = "Nanoleaf ajouté. \(synced.count) lampe(s) synchronisée(s)."
        }
    }

    func removeNanoleafDevice(_ device: NanoleafDevice) async {
        var next = nanoleafSettings
        next.devices.removeAll { $0.id == device.id }
        await runBusy {
            nanoleafSettings = try nanoleafSettingsStore.save(next)
            lightProviders[.nanoleaf] = nil
            let synced = try await syncConfiguredProviders()
            lamps = synced
            selectedLampIds = selectedLampIds.intersection(Set(synced.map(\.id)))
            expandedLampIds = expandedLampIds.intersection(Set(synced.map(\.id)))
            lastSyncDate = Date()
            message = "Nanoleaf retiré."
        }
    }

    private func loadNanoleafSettings() {
        do { nanoleafSettings = try nanoleafSettingsStore.load() } catch { }
    }

    // MARK: - WiZ

    func addWizDevice(host: String, name: String) async {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty else { message = "Adresse IP WiZ requise."; return }

        let device = WizDevice(name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? cleanHost : name.trimmingCharacters(in: .whitespacesAndNewlines),
                               host: cleanHost)
        var next = wizSettings
        next.devices.append(device)

        await runBusy {
            wizSettings = try wizSettingsStore.save(next)
            lightProviders[.wiz] = nil
            let synced = try await syncConfiguredProviders()
            lamps = synced
            selectedLampIds = selectedLampIds.intersection(Set(synced.map(\.id)))
            expandedLampIds = expandedLampIds.intersection(Set(synced.map(\.id)))
            lastSyncDate = Date()
            message = "WiZ ajoutée. \(synced.count) lampe(s) synchronisée(s)."
        }
    }

    func removeWizDevice(_ device: WizDevice) async {
        var next = wizSettings
        next.devices.removeAll { $0.id == device.id }
        await runBusy {
            wizSettings = try wizSettingsStore.save(next)
            lightProviders[.wiz] = nil
            let synced = try await syncConfiguredProviders()
            lamps = synced
            selectedLampIds = selectedLampIds.intersection(Set(synced.map(\.id)))
            expandedLampIds = expandedLampIds.intersection(Set(synced.map(\.id)))
            lastSyncDate = Date()
            message = "WiZ retirée."
        }
    }

    private func loadWizSettings() {
        do { wizSettings = try wizSettingsStore.load() } catch { }
    }

    // MARK: - Shortcuts

    func executeShortcutAction(_ action: ShortcutAction) {
        Task { @MainActor in
            switch action {
            case .powerOffAll:     await applyPowerAll(false)
            case .powerOnAll:      await applyPowerAll(true)
            case .applySceneFocus:
                if let p = LightScenePreset.presets.first(where: { $0.id == "focus" }) { await applyScene(p) }
            case .applySceneRelax:
                if let p = LightScenePreset.presets.first(where: { $0.id == "relax" }) { await applyScene(p) }
            case .applySceneNeon:
                if let p = LightScenePreset.presets.first(where: { $0.id == "neon" })  { await applyScene(p) }
            case .applySceneNight:
                if let p = LightScenePreset.presets.first(where: { $0.id == "night" }) { await applyScene(p) }
            }
        }
    }

    func applyPowerAll(_ value: Bool) async {
        let targets = lamps.filter { $0.online }
        guard !targets.isEmpty else { return }
        await runBusy {
            var updated: [LampDevice] = []
            for lamp in targets {
                updated.append(try await makeLightProvider(for: lamp).setPower(deviceId: lamp.nativeID, value: value))
            }
            for lamp in updated { updateLamp(lamp) }
            message = value ? "Toutes les lampes allumées." : "Toutes les lampes éteintes."
        }
    }

    func saveShortcutSettings() async {
        await runBusy {
            shortcutSettings = try shortcutSettingsStore.save(shortcutSettings)
            message = "Raccourcis enregistrés."
        }
        NotificationCenter.default.post(name: .shortcutSettingsDidChange, object: nil)
    }

    private func loadShortcutSettings() {
        shortcutSettings = (try? shortcutSettingsStore.load()) ?? .default
    }

    // MARK: - Automations

    func saveAutomation(_ automation: Automation) {
        guard licenseState.entitlements.canUseAutomations else {
            message = "Les automations sont incluses dans Premium."
            return
        }
        if let idx = automations.firstIndex(where: { $0.id == automation.id }) {
            automations[idx] = automation
        } else {
            automations.append(automation)
        }
        try? automationStore.save(automations)
        automationScheduler.update(automations: automations)
        message = "Automation « \(automation.name) » enregistrée."
    }

    func deleteAutomation(_ automation: Automation) {
        automations.removeAll { $0.id == automation.id }
        try? automationStore.save(automations)
        automationScheduler.update(automations: automations)
        message = "Automation supprimée."
    }

    func toggleAutomation(_ automation: Automation) {
        guard let idx = automations.firstIndex(where: { $0.id == automation.id }) else { return }
        automations[idx].isEnabled.toggle()
        try? automationStore.save(automations)
        automationScheduler.update(automations: automations)
    }

    func executeAutomationAction(_ action: AutomationAction) async {
        switch action {
        case .powerOffAll:
            await applyPowerAll(false)
        case .powerOnAll:
            await applyPowerAll(true)
        case .applyScenePreset(let id):
            if let preset = LightScenePreset.presets.first(where: { $0.id == id }) {
                await applyScene(preset)
            }
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
            Task { await self.executeAutomationAction(automation.action) }
        }
        automationScheduler.start(with: automations)
    }

    private func loadAutomations() {
        automations = (try? automationStore.load()) ?? []
    }

    // MARK: - Adaptive Lighting

    func setAdaptiveLighting(enabled: Bool) async {
        guard licenseState.entitlements.canUseAdaptiveLighting || !enabled else {
            message = "L'éclairage adaptatif est inclus dans Premium."
            return
        }
        circadianSettings.isEnabled = enabled
        _ = try? circadianSettingsStore.save(circadianSettings)
        if enabled {
            circadianService.start(with: circadianSettings)
        } else {
            circadianService.stop()
        }
    }

    func saveCircadianSettings(_ settings: CircadianSettings) async {
        await runBusy {
            circadianSettings = try circadianSettingsStore.save(settings)
            circadianService.start(with: circadianSettings)
            message = "Réglages adaptatifs enregistrés."
        }
    }

    func applyCircadianNow() async {
        guard circadianSettings.isEnabled else { return }
        let (brightness, temperature) = circadianService.currentValues()
        let targets = lamps.filter { $0.online }
        await runBusy {
            for lamp in targets {
                let provider = try makeLightProvider(for: lamp)
                if circadianSettings.applyBrightness, lamp.capabilities.brightness != nil {
                    _ = try? await provider.setBrightness(deviceId: lamp.nativeID, value: brightness)
                }
                if circadianSettings.applyTemperature, lamp.capabilities.temperature != nil {
                    _ = try? await provider.setTemperature(deviceId: lamp.nativeID, value: temperature)
                }
            }
            message = "Éclairage adaptatif appliqué (\(brightness)%, \(temperature)K)."
        }
    }

    func startCircadianService() {
        circadianService.onApply = { [weak self] brightness, temperature in
            guard let self else { return }
            Task { await self.applyCircadianNow() }
        }
        if circadianSettings.isEnabled {
            circadianService.start(with: circadianSettings)
        }
    }

    private func loadCircadianSettings() {
        circadianSettings = (try? circadianSettingsStore.load()) ?? .default
    }

    private func presentOnboardingIfNeeded() {
        guard !canSync else {
            isOnboardingPresented = false
            return
        }

        isOnboardingPresented = !UserDefaults.standard.bool(forKey: onboardingDismissedKey)
    }

    private func loadScenes() {
        do {
            userScenes = try sceneStore.load()
        } catch {
            message = "Scènes locales illisibles."
        }
    }

    private func loadLicense() {
        do {
            licenseState = try licenseStore.load()

            // Validate license with provider asynchronously at startup to prevent
            // local tampering of license.json (if the file was edited to be premium).
            Task { [weak self] in
                guard let self = self else { return }
                do {
                    let validated = try await licenseActivationService.validate(self.licenseState)
                    await MainActor.run {
                        self.licenseState = validated
                        do {
                            try self.licenseStore.save(validated)
                        } catch {
                            // non-fatal: keep in-memory state
                        }
                    }
                } catch {
                    // Validation failed: downgrade to early access and persist.
                    await MainActor.run {
                        self.licenseState = .earlyAccess
                        try? self.licenseStore.save(self.licenseState)
                        self.message = "Licence non validée en ligne. Early Access actif."
                    }
                }
            }
        } catch {
            licenseState = .earlyAccess
            message = "Licence locale illisible. Early Access actif."
        }
    }

    private func persistScenes() {
        do {
            try sceneStore.save(userScenes)
        } catch {
            message = error.localizedDescription
        }
    }

    private func updateLamp(_ next: LampDevice) {
        lamps = lamps.map { $0.id == next.id ? next : $0 }
        persistWidgetSnapshot()
    }

    private func startAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                await self?.syncLamps(silent: true)
            }
        }
    }

    private func runBusy(_ operation: () async throws -> Void) async {
        isBusy = true
        message = ""
        defer { isBusy = false }

        do {
            try await operation()
        } catch {
            message = error.localizedDescription
        }
    }

    private func persistWidgetSnapshot() {
        let snapshot = WidgetDashboardSnapshot(
            totalLampCount: lamps.count,
            onlineLampCount: lamps.filter(\.online).count,
            poweredOnLampCount: lamps.filter(\.power).count,
            sceneCount: userScenes.count,
            sceneTitles: userScenes.map(\.title),
            activeRoomCount: rooms.count,
            roomTitles: rooms.map(\.name)
        )

        try? widgetSnapshotStore.save(snapshot)
    }
}

enum ControlTab {
    case lamps
    case settings
}
