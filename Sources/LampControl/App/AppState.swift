import AppKit
import Foundation
import OSLog
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
    @Published var settings = TuyaSettings()
    @Published var hueSettings = HueSettings()
    @Published var lifxSettings = LifxSettings()
    @Published var goveeSettings = GoveeSettings()
    @Published var yeelightSettings = YeelightSettings()
    @Published var discoveredYeelightBulbs: [YeelightDiscoveredBulb] = []
    @Published var isSearchingYeelight = false
    /// True once a manual network search finished (so the UI can say "none found").
    @Published var yeelightSearchCompleted = false
    @Published var nanoleafSettings = NanoleafSettings()
    @Published var wizSettings = WizSettings()
    @Published var shortcutSettings = ShortcutSettings.default
    @Published var automations: [Automation] = []
    @Published var circadianSettings = CircadianSettings.default
    @Published var discoveredHueBridges: [HueBridge] = []
    @Published var lamps: [LampDevice] = []
    @Published var selectedTab: ControlTab = .lamps
    /// Banner text. Informational messages auto-hide after a few seconds;
    /// errors (set via `showError`) stay until the next message.
    @Published var message = "" {
        didSet {
            messageIsError = false
            scheduleMessageDismiss()
        }
    }
    @Published private(set) var messageIsError = false
    private var messageDismissTask: Task<Void, Never>?
    private var pendingAdaptiveNotice = false
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
    private let yeelightLiveSync = YeelightLiveSync()
    /// Coalesces and paces what sliders / the color picker stream while the user drags.
    private lazy var commandQueue: LampCommandQueue = makeCommandQueue()
    /// Lamps that were off when the user started adjusting their color: the first command
    /// must switch them on (many bulbs reject color commands while off).
    private var lampsNeedingPowerOn = Set<String>()
    /// Keeps the user's value on screen while they adjust a lamp (see `LampInteractionGuard`).
    private var interactionGuard = LampInteractionGuard()
    private var holdExpiryTasks: [String: Task<Void, Never>] = [:]
    private var lastYeelightDiscovery: Date?
    private var isRecoveringYeelight = false
    /// Minimum delay between automatic (background) network searches.
    private let yeelightDiscoveryInterval: TimeInterval = 5 * 60
    private let onboardingDismissedKey = "LampControl.onboarding.dismissed"
    /// True while "Reset all settings" runs: blocks background persistence so
    /// nothing re-creates the files that were just removed.
    private var isResettingApp = false

    init() {
        configureYeelightLiveSync()
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
            finishFocusAutomationSetup()
            reconcileYeelightLiveSync()
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
            showError(L10n.roomsSaveFailed)
        }
    }

    func persistRooms() {
        guard !isResettingApp else { return }
        do {
            try roomStore.saveRooms(rooms)
        } catch {
            showError(L10n.roomsSaveFailed)
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
        guard !targets.isEmpty else { showError(L10n.roomNoOnlineLamp); return }

        await runBusy {
            var updated: [LampDevice] = []
            for lamp in targets {
                updated.append(try await makeLightProvider(for: lamp).setPower(deviceId: lamp.nativeID, value: value))
            }
            for lamp in updated { updateLamp(lamp) }
            message = L10n.roomPower(value)
        }
    }

    func applyScene(_ scene: UserLightScene, toRoomId roomId: String, byUser: Bool = false) async {
        guard canApply(scene) else {
            message = L10n.premiumScenes
            return
        }

        guard let room = rooms.first(where: { $0.id == roomId }) else { return }
        let targets = lamps.filter { room.lampIds.contains($0.id) && $0.online && $0.capabilities.colorCode != nil }
        guard !targets.isEmpty else { showError(L10n.roomNoOnlineRGB); return }
        if byUser { await pauseAdaptiveForScene() }

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
                    updated.append(try await applyColor(scene.color, to: lamp))
                }
            }

            for lamp in updated { updateLamp(lamp) }
            message = L10n.roomSceneApplied(scene.title)
        }
    }

    // MARK: - Focus Mode Mappings

    func loadFocusMappings() {
        focusMappings = focusMappingStore.loadMappings()
    }

    func persistFocusMappings() {
        guard !isResettingApp else { return }
        do {
            try focusMappingStore.saveMappings(focusMappings)
        } catch {
            showError(L10n.focusSaveFailed)
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

    // MARK: Launch at login

    /// Mirrors `SMAppService.mainApp.status`; refreshed on demand (Settings appear / after a change).
    @Published private(set) var loginItemStatus: SMAppService.Status = SMAppService.mainApp.status

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
            let key = enabled ? "login.item.error.register" : "login.item.error.unregister"
            message = String(format: NSLocalizedString(key, comment: ""), error.localizedDescription)
        }
        refreshLoginItemStatus()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: Focus automation (URL scheme)

    private static let focusLog = Logger(subsystem: "fr.hugoinformatique.lampcontrol", category: "FocusAutomation")
    private var isFocusAutomationReady = false
    private var pendingFocusURLs: [URL] = []

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

        guard licenseState.entitlements.canUseFocusMappings else {
            Self.focusLog.info("Focus automation ignored: Premium feature")
            return
        }

        switch event {
        case .off:
            currentFocusIdentifier = nil
        case .activate(let mode):
            guard let known = knownFocusIdentifiers.first(where: { $0.caseInsensitiveCompare(mode) == .orderedSame }) else {
                Self.focusLog.error("Ignoring unknown focus mode: \(mode, privacy: .public)")
                return
            }
            currentFocusIdentifier = known
            Task { await applySceneForCurrentFocus() }
        }
    }

    private func finishFocusAutomationSetup() {
        isFocusAutomationReady = true
        let pending = pendingFocusURLs
        pendingFocusURLs = []
        pending.forEach(handleFocusURL)
    }

    deinit {
        autoSyncTask?.cancel()
    }

    var canSync: Bool {
        // Was missing Nanoleaf and WiZ, so users with only those could not sync.
        !configuredProviderKinds.isEmpty
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
        guard !isResettingApp else { return }
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
            showError(error)
        }
    }

    func saveLifxSettingsAndSync() async {
        await runBusy {
            lifxSettings = try lifxSettingsStore.save(lifxSettings)
            lightProviders[.lifx] = nil
            let synced = try await syncConfiguredProviders()
            setSyncedLamps(synced)
            selectedLampIds = selectedLampIds.intersection(Set(synced.map(\.id)))
            expandedLampIds = expandedLampIds.intersection(Set(synced.map(\.id)))
            lastSyncDate = Date()
            message = L10n.lifxConnected(synced.count)
            selectedTab = .lamps
        }
    }

    func saveGoveeSettingsAndSync() async {
        await runBusy {
            goveeSettings = try goveeSettingsStore.save(goveeSettings)
            lightProviders[.govee] = nil
            let synced = try await syncConfiguredProviders()
            setSyncedLamps(synced)
            selectedLampIds = selectedLampIds.intersection(Set(synced.map(\.id)))
            expandedLampIds = expandedLampIds.intersection(Set(synced.map(\.id)))
            lastSyncDate = Date()
            message = L10n.goveeConnected(synced.count)
            selectedTab = .lamps
        }
    }

    func addYeelightBulb(host: String, name: String, deviceId: String? = nil) async {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty else {
            showError(L10n.yeelightIPRequired)
            return
        }

        var (hostOnly, port) = parseYeelightHost(cleanHost)
        if hostOnly.isEmpty { hostOnly = cleanHost; port = 55443 }

        var next = yeelightSettings
        let normalizedID = deviceId?.lowercased()
        if next.bulbs.contains(where: { existing in
            (normalizedID != nil && existing.deviceId == normalizedID) || (existing.host == hostOnly && existing.port == port)
        }) {
            return
        }
        let bulb = YeelightBulb(host: hostOnly, port: port, name: name.trimmingCharacters(in: .whitespacesAndNewlines), deviceId: deviceId)
        next.bulbs.append(bulb)

        await runBusy {
            yeelightSettings = try yeelightSettingsStore.save(next)
            lightProviders[.yeelight] = nil
            let synced = try await syncConfiguredProviders()
            setSyncedLamps(synced)
            selectedLampIds = selectedLampIds.intersection(Set(synced.map(\.id)))
            expandedLampIds = expandedLampIds.intersection(Set(synced.map(\.id)))
            lastSyncDate = Date()
            message = L10n.yeelightAdded(synced.count)
            reconcileYeelightLiveSync()
        }
    }

    func removeYeelightBulb(_ bulb: YeelightBulb) async {
        var next = yeelightSettings
        next.bulbs.removeAll { $0.id == bulb.id }

        await runBusy {
            yeelightSettings = try yeelightSettingsStore.save(next)
            lightProviders[.yeelight] = nil
            let synced = try await syncConfiguredProviders()
            setSyncedLamps(synced)
            selectedLampIds = selectedLampIds.intersection(Set(synced.map(\.id)))
            expandedLampIds = expandedLampIds.intersection(Set(synced.map(\.id)))
            lastSyncDate = Date()
            message = L10n.yeelightRemoved
            reconcileYeelightLiveSync()
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
            message = L10n.settingsSaved
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
            setSyncedLamps(synced)
            selectedLampIds = selectedLampIds.intersection(Set(synced.map(\.id)))
            expandedLampIds = expandedLampIds.intersection(Set(synced.map(\.id)))
            lastSyncDate = Date()
            message = synced.isEmpty ? L10n.settingsSavedNoneFound : L10n.lampsSynced(synced.count)
            selectedTab = .lamps
        }
    }

    func syncLamps(silent: Bool = false) async {
        guard canSync else { return }

        if silent {
            guard !isBusy && !isAutoSyncing else { return }
            // Don't poll bulbs while the user is adjusting one: the reply would be stale on arrival.
            guard !interactionGuard.isAnyHolding(now: Date()), commandQueue.isAllIdle else { return }
            isAutoSyncing = true
            defer { isAutoSyncing = false }

            do {
                let synced = try await syncConfiguredProviders()
                setSyncedLamps(synced)
                selectedLampIds = selectedLampIds.intersection(Set(synced.map(\.id)))
                expandedLampIds = expandedLampIds.intersection(Set(synced.map(\.id)))
                lastSyncDate = Date()
                persistWidgetSnapshot()
                scheduleYeelightRecovery()
            } catch {
                // Silent refresh should not interrupt normal use.
            }

            return
        }

        await runBusy {
            let synced = try await syncConfiguredProviders()
            setSyncedLamps(synced)
            selectedLampIds = selectedLampIds.intersection(Set(synced.map(\.id)))
            expandedLampIds = expandedLampIds.intersection(Set(synced.map(\.id)))
            lastSyncDate = Date()
            message = synced.isEmpty ? L10n.lampsNoneFound : L10n.lampsSynced(synced.count)
            persistWidgetSnapshot()
            scheduleYeelightRecovery()
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
            showError(error)
            return false
        }
    }

    // MARK: - Live adjustments (sliders, color picker)
    //
    // `preview*` runs on every drag event: it updates the UI immediately and, for providers
    // that declare a `liveUpdatePolicy`, hands the value to the coalescing queue so the lamp
    // follows while the user is still dragging. `commit*` runs once on release with the final
    // value, which always goes out. Providers without a policy only receive the final value.

    /// The user grabbed a control of `lamp`: from now on state coming from elsewhere is
    /// ignored for it until they are done (see `LampInteractionGuard`).
    func beginAdjusting(_ lamp: LampDevice) {
        interactionGuard.beginDrag(lamp.id, now: Date())
        scheduleHoldExpiry(for: lamp.id)
    }

    func previewBrightness(_ lamp: LampDevice, value: Int) {
        noteUserActivity(lamp.id)
        updateLamp(lamp.withBrightness(value))
        enqueue(.brightness(value), for: lamp, isFinal: false)
    }

    func commitBrightness(_ lamp: LampDevice, value: Int) async {
        endUserActivity(lamp.id)
        enqueue(.brightness(value), for: lamp, isFinal: true)
    }

    func previewTemperature(_ lamp: LampDevice, value: Int) {
        noteUserActivity(lamp.id)
        updateLamp(lamp.withTemperature(value))
        enqueue(.temperature(value), for: lamp, isFinal: false)
    }

    func commitTemperature(_ lamp: LampDevice, value: Int) async {
        endUserActivity(lamp.id)
        enqueue(.temperature(value), for: lamp, isFinal: true)
    }

    func previewColor(_ lamp: LampDevice, color: HSVColor) {
        noteUserActivity(lamp.id)
        if !lamp.power { lampsNeedingPowerOn.insert(lamp.id) }
        updateLamp(lamp.previewingColor(color))
        enqueue(.color(color), for: lamp, isFinal: false)
    }

    func commitColor(_ lamp: LampDevice, color: HSVColor) async {
        endUserActivity(lamp.id)
        if !lamp.power { lampsNeedingPowerOn.insert(lamp.id) }
        enqueue(.color(color), for: lamp, isFinal: true)
    }

    // MARK: - Stale update protection

    private func isHolding(_ lampID: String) -> Bool {
        interactionGuard.isHolding(lampID, now: Date(), commandsPending: !commandQueue.isIdle(lampID))
    }

    private func noteUserActivity(_ lampID: String) {
        interactionGuard.touch(lampID, now: Date())
        scheduleHoldExpiry(for: lampID)
    }

    private func endUserActivity(_ lampID: String) {
        interactionGuard.endDrag(lampID, now: Date())
        scheduleHoldExpiry(for: lampID)
    }

    /// Waits for the user's window on `lampID` to close (it keeps getting pushed out by new
    /// activity and by command replies), then reconciles with what the bulb really reports.
    private func scheduleHoldExpiry(for lampID: String) {
        guard holdExpiryTasks[lampID] == nil else { return }
        holdExpiryTasks[lampID] = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard let end = self.interactionGuard.holdEnd(lampID) else { break }
                let remaining = end.timeIntervalSinceNow
                if remaining > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000) + 50_000_000)
                    continue
                }
                if !self.commandQueue.isIdle(lampID) {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    continue
                }
                self.interactionGuard.clear(lampID)
                self.reconcileAfterInteraction(lampID)
                break
            }
            self?.holdExpiryTasks[lampID] = nil
        }
    }

    /// The window closed: show the bulb's own latest state (this also corrects the UI if a
    /// command was lost). Other providers have no push channel; their next poll does it.
    private func reconcileAfterInteraction(_ lampID: String) {
        guard let lamp = lamps.first(where: { $0.id == lampID }), lamp.providerID == .yeelight,
              let bulb = yeelightSettings.bulbs.first(where: { $0.id == lamp.nativeID }),
              let live = yeelightLiveSync.liveProperties(for: bulb.id)
        else { return }
        applyYeelightLiveState(bulb: bulb, properties: live, online: true)
    }

    private func enqueue(_ command: LampCommand, for lamp: LampDevice, isFinal: Bool) {
        let policy = (try? makeLightProvider(for: lamp))?.liveUpdatePolicy
        guard isFinal || policy != nil else { return }
        commandQueue.submit(lampID: lamp.id, command: command, isFinal: isFinal, policy: policy)
    }

    private func makeCommandQueue() -> LampCommandQueue {
        let queue = LampCommandQueue { [weak self] lampID, command, transition in
            guard let self else { return nil }
            return try await self.perform(command, lampID: lampID, transition: transition)
        }
        queue.onApplied = { [weak self] lampID, lamp in
            guard let self else { return }
            self.interactionGuard.touch(lampID, now: Date())
            self.updateLamp(lamp)
        }
        queue.onIdle = { [weak self] lampID in
            guard let self else { return }
            // The grace period counts from the last command's reply.
            self.interactionGuard.touch(lampID, now: Date())
            self.scheduleHoldExpiry(for: lampID)
        }
        queue.onFailure = { [weak self] lampID, error in
            guard let self else { return }
            self.lampsNeedingPowerOn.remove(lampID)
            self.showError(error)
        }
        return queue
    }

    private func perform(_ command: LampCommand, lampID: String, transition: TimeInterval) async throws -> LampDevice? {
        guard var lamp = lamps.first(where: { $0.id == lampID }) else { return nil }
        if lampsNeedingPowerOn.remove(lampID) != nil { lamp.power = false }
        let provider = try makeLightProvider(for: lamp)
        switch command {
        case .brightness(let value):
            return try await provider.setBrightness(deviceId: lamp.nativeID, value: value, transition: transition)
        case .temperature(let value):
            return try await provider.setTemperature(deviceId: lamp.nativeID, value: value, transition: transition)
        case .color(let color):
            return try await applyColor(color, to: lamp, transition: transition)
        }
    }

    func toggleSelection(_ lamp: LampDevice) {
        guard licenseState.entitlements.canUseGroups else {
            message = L10n.premiumGroups
            return
        }

        if selectedLampIds.contains(lamp.id) {
            selectedLampIds.remove(lamp.id)
        } else {
            selectedLampIds.insert(lamp.id)
        }

        isGroupPanelExpanded = selectedLampIds.count >= 2
    }

    /// Groups only make sense with at least two color lamps; with a single
    /// bulb the group bar and the per-lamp "Add to group" toggle were noise.
    /// Search / hide-offline row: pointless with one or two lamps. Stays visible
    /// while a filter is active so the user can always switch it off again.
    var showsLampFilters: Bool {
        lamps.count > 2 || hideOfflineLamps || !searchText.isEmpty
    }

    var showsGroupControls: Bool {
        lamps.lazy.filter { $0.capabilities.colorCode != nil }.prefix(2).count >= 2
    }

    func selectAllRGBLamps() {
        guard licenseState.entitlements.canUseGroups else {
            message = L10n.premiumGroups
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
        // a content-aware target capped at 860pt. Anything beyond scrolls
        // (rooms, expanded rows, scene editor).
        case .lamps:    height = lampsPopoverHeight
        }
        let screenMax = (popoverScreenVisibleHeight ?? NSScreen.main?.visibleFrame.height ?? 900) - 80
        return min(max(height, 360), screenMax)
    }

    /// Visible height of the display the popover opens on. `NSScreen.main` is
    /// the display with the key window — often the *other* monitor — so a
    /// popover sized for a taller screen did not fit and AppKit shifted it
    /// away from the menu bar icon.
    @Published var popoverScreenVisibleHeight: CGFloat?

    private var lampsPopoverHeight: CGFloat {
        // Quiet Glass v2: tab strip removed (gear/back lives in the header).
        // header 56 + outer paddings 28 = ~84pt fixed chrome
        var h: CGFloat = 84

        // The message banner is not reserved: resizing the popover each time a
        // banner appeared/disappeared caused flicker; the ScrollView absorbs it.

        // status bar card (~56pt)
        h += 56 + 12

        // No providers configured → just show onboarding card.
        if !canSync {
            return min(h + 220, 540)
        }

        // search + offline toggle row
        if showsLampFilters { h += 44 }

        // empty/filter empty state card
        if lamps.isEmpty && !isAutoSyncing { return min(h + 200, 540) }

        if lamps.contains(where: { $0.capabilities.colorCode != nil }) {
            h += 84   // ScenePresetBar
        }
        if showsGroupControls {
            h += isGroupPanelExpanded || selectedLampIds.count >= 2 ? 220 : 60
        }
        if hiddenLampCount > 0 { h += 56 }

        // Reserve room for every visible lamp row (expanded rows at their full
        // height) + room headers. Previously capped at 3 rows / 620 pt, so two
        // expanded lamps already did not fit; the screen height is the real
        // limit (see preferredPopoverHeight), the ScrollView absorbs the rest.
        for lamp in visibleLamps {
            h += expandedLampIds.contains(lamp.id) ? expandedLampRowHeight(for: lamp) : 72
        }

        let roomsWithLamps = rooms.filter { room in visibleLamps.contains(where: { room.lampIds.contains($0.id) }) }.count
        h += CGFloat(roomsWithLamps) * 48

        return min(h, 860)
    }

    private func expandedLampRowHeight(for lamp: LampDevice) -> CGFloat {
        var height: CGFloat = 62

        if showsGroupControls { height += 37 }   // "Add to group" row

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
            message = L10n.premiumGroups
            return
        }

        let targets = lamps.filter { selectedLampIds.contains($0.id) && canShow(groupColor, on: $0) }
        guard !targets.isEmpty else {
            showError(L10n.selectRGBLamp)
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
            message = L10n.colorApplied(updated.count)
        }
    }

    /// `byUser`: the user picked this scene (UI or keyboard shortcut), as
    /// opposed to an automation / Focus trigger. A user-picked scene turns
    /// adaptive lighting off, otherwise it would overwrite the scene within
    /// 15 minutes.
    func applyScene(_ preset: LightScenePreset, byUser: Bool = false) async {
        await applyScene(title: preset.title, color: preset.color, byUser: byUser)
    }

    /// Built-in presets were always free; now that they live in the scene list
    /// as regular scenes, applying an (unmodified-kind) preset-derived scene
    /// stays free too. Everything else needs custom-scene entitlement.
    private func canApply(_ scene: UserLightScene) -> Bool {
        let e = licenseState.entitlements
        if e.canUseCustomScenes { return true }
        return scene.presetId != nil && !scene.isCapture && e.canUseScenePresets
    }

    /// Applies a built-in by id ("focus", "relax"...): the user's (possibly
    /// edited) scene when it still exists, else the hard-coded definition, so
    /// shortcuts and automations keep working even if the scene was deleted.
    func applyPreset(id: String, byUser: Bool = false) async {
        if let scene = PresetScenes.scene(forPresetId: id, in: userScenes) {
            await applyScene(scene, byUser: byUser)
        } else if let preset = LightScenePreset.preset(id: id) {
            await applyScene(preset, byUser: byUser)
        }
    }

    func applyScene(_ scene: UserLightScene, byUser: Bool = false) async {
        guard canApply(scene) else {
            message = L10n.premiumScenes
            return
        }

        if let snapshots = scene.snapshots {
            await applyCapture(snapshots: snapshots, name: scene.title, byUser: byUser)
        } else {
            await applyScene(title: scene.title, color: scene.color, byUser: byUser)
        }
    }

    func saveUserScene(id: UUID?, title: String, icon: String, color: HSVColor, snapshots: [LampSnapshot]? = nil) {
        guard licenseState.entitlements.canUseCustomScenes else {
            message = L10n.premiumScenes
            return
        }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { showError(L10n.sceneNameRequired); return }
        let cleanIcon = icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "paintpalette.fill" : icon.trimmingCharacters(in: .whitespacesAndNewlines)

        if let id, let index = userScenes.firstIndex(where: { $0.id == id }) {
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
        if byUser { await pauseAdaptiveForScene() }
        await runBusy {
            var updated: [LampDevice] = []
            for snap in snapshots {
                guard let lamp = lamps.first(where: { $0.id == snap.lampId && $0.online }) else { continue }
                let provider = try makeLightProvider(for: lamp)
                // Many bulbs (e.g. Yeelight) reject color commands while off.
                if snap.power, !lamp.power {
                    updated.append(try await provider.setPower(deviceId: lamp.nativeID, value: true))
                }
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
            message = L10n.sceneApplied(name)
        }
    }

    func deleteUserScene(_ scene: UserLightScene) {
        guard licenseState.entitlements.canUseCustomScenes else {
            message = L10n.premiumScenes
            return
        }

        userScenes.removeAll { $0.id == scene.id }
        persistScenes()
        persistWidgetSnapshot()
        message = L10n.sceneDeleted
    }

    private func applyScene(title: String, color: HSVColor, byUser: Bool) async {
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
        if byUser { await pauseAdaptiveForScene() }

        groupColor = color

        await runBusy {
            var updated: [LampDevice] = []
            for lamp in targets {
                updated.append(try await applyColor(color, to: lamp))
            }
            for lamp in updated {
                updateLamp(lamp)
            }
            message = selectedTargets.isEmpty
                ? L10n.ambianceAppliedToAll(title)
                : L10n.ambianceApplied(title, count: updated.count)
        }
    }

    func applyGroupPower(_ value: Bool) async {
        guard licenseState.entitlements.canUseGroups else {
            message = L10n.premiumGroups
            return
        }

        let targets = lamps.filter { selectedLampIds.contains($0.id) }
        guard !targets.isEmpty else {
            showError(L10n.selectLamp)
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
            message = L10n.groupPower(value)
        }
    }

    func activateLicense(_ licenseKey: String, email: String?) async {
        await runBusy {
            let next = try await licenseActivationService.activate(licenseKey: licenseKey, expectedEmail: email)
            licenseState = next
            try licenseStore.save(next)
            message = L10n.premiumPurchaseRegistered
        }
    }

    func validateLicense() async {
        await runBusy {
            let next = try await licenseActivationService.validate(licenseState)
            licenseState = next
            try licenseStore.save(next)
            message = next.tier == .premium ? L10n.premiumActivated : L10n.premiumNotDetected
        }
    }

    func deactivateLicense() async {
        await runBusy {
            if licenseState.tier == .premium {
                try await licenseActivationService.deactivate(licenseState)
            }

            licenseState = .earlyAccess
            try licenseStore.save(licenseState)
            message = L10n.localStateReset
        }
    }

    func openPremiumCheckout() {
        Task { await activateLicense("", email: nil) }
    }

    func discoverHueBridges() async {
        await runBusy {
            discoveredHueBridges = try await hueClient.discoverBridges()
            message = discoveredHueBridges.isEmpty ? L10n.hueNoneFound : L10n.hueBridgesFound(discoveredHueBridges.count)
        }
    }

    func selectHueBridge(_ bridge: HueBridge) {
        hueSettings.bridgeID = bridge.id
        hueSettings.bridgeIP = bridge.internalipaddress
        message = L10n.hueBridgeSelected
    }

    func pairHueBridge() async {
        await runBusy {
            let bridgeIP = hueSettings.bridgeIP.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bridgeIP.isEmpty else {
                throw LampControlError.configuration(L10n.hueBridgeRequired)
            }

            hueSettings.username = try await hueClient.createUser(bridgeIP: bridgeIP)
            hueSettings = try hueSettingsStore.save(hueSettings)
            lightProviders[.philipsHue] = nil
            message = L10n.hueBridgeConnected
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
    private func applyColor(_ color: HSVColor, to lamp: LampDevice, transition: TimeInterval = 0.2) async throws -> LampDevice {
        let provider = try makeLightProvider(for: lamp)
        // Many bulbs (e.g. Yeelight) reject color/CT/brightness commands while
        // off; applying a color implies the lamp should light up.
        if !lamp.power {
            _ = try await provider.setPower(deviceId: lamp.nativeID, value: true)
        }
        guard color.isNearWhite, let temperature = lamp.capabilities.temperature else {
            return try await provider.setColor(deviceId: lamp.nativeID, color: color, transition: transition)
        }

        var updated = try await provider.setTemperature(
            deviceId: lamp.nativeID,
            value: LampDevice.neutralWhite(for: temperature),
            transition: transition
        )
        if let brightness = lamp.capabilities.brightness {
            let value = LampDevice.brightness(forColorValue: color.v, capability: brightness)
            updated = try await provider.setBrightness(deviceId: lamp.nativeID, value: value, transition: transition)
        }
        return updated
    }

    /// Closes the menu-bar popover without quitting. Set by `AppDelegate`.
    var closePopover: (() -> Void)?

    func quit() {
        yeelightLiveSync.stopAll()
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
                throw LampControlError.configuration(NSLocalizedString("error.hue.not.configured", comment: ""))
            }
            provider = HueLightProvider(settings: hueSettings)
        case .lifx:
            guard lifxSettings.isConfigured else {
                throw LampControlError.configuration(NSLocalizedString("error.lifx.token.missing", comment: ""))
            }
            provider = LifxLightProvider(settings: lifxSettings)
        case .govee:
            guard goveeSettings.isConfigured else {
                throw LampControlError.configuration(NSLocalizedString("error.govee.apikey.missing", comment: ""))
            }
            provider = GoveeLightProvider(settings: goveeSettings)
        case .yeelight:
            guard yeelightSettings.isConfigured else {
                throw LampControlError.configuration(NSLocalizedString("error.yeelight.none", comment: ""))
            }
            provider = YeelightLightProvider(settings: yeelightSettings)
        case .nanoleaf:
            guard nanoleafSettings.isConfigured else {
                throw LampControlError.configuration(NSLocalizedString("error.nanoleaf.none", comment: ""))
            }
            provider = NanoleafLightProvider(settings: nanoleafSettings)
        case .wiz:
            guard wizSettings.isConfigured else {
                throw LampControlError.configuration(NSLocalizedString("error.wiz.none", comment: ""))
            }
            provider = WizLightProvider(settings: wizSettings)
        }

        lightProviders[kind] = provider
        return provider
    }

    private func makeTuyaProvider() throws -> TuyaLightProvider {
        let secret = try settingsStore.accessSecret()
        guard !settings.accessId.isEmpty, !secret.isEmpty, !settings.endpoint.isEmpty, !settings.uid.isEmpty else {
            throw LampControlError.configuration(L10n.tuyaCredentialsIncomplete)
        }

        let client = try TuyaClient(accessId: settings.accessId, accessSecret: secret, endpoint: settings.endpoint)
        let service = TuyaLightProvider(client: client, uid: settings.uid)
        return service
    }

    private func loadHueSettings() {
        do {
            hueSettings = try hueSettingsStore.load()
        } catch {
            showError(L10n.settingsUnreadable("Hue"))
        }
    }

    private func loadLifxSettings() {
        do {
            lifxSettings = try lifxSettingsStore.load()
        } catch {
            showError(L10n.settingsUnreadable("LIFX"))
        }
    }

    private func loadGoveeSettings() {
        do {
            goveeSettings = try goveeSettingsStore.load()
        } catch {
            showError(L10n.settingsUnreadable("Govee"))
        }
    }

    private func loadYeelightSettings() {
        do {
            yeelightSettings = try yeelightSettingsStore.load()
        } catch {
            showError(L10n.settingsUnreadable("Yeelight"))
        }
    }

    // MARK: - Nanoleaf

    func addNanoleafDevice(host: String, name: String) async {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty else { showError(L10n.nanoleafIPRequired); return }

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
            setSyncedLamps(synced)
            selectedLampIds = selectedLampIds.intersection(Set(synced.map(\.id)))
            expandedLampIds = expandedLampIds.intersection(Set(synced.map(\.id)))
            lastSyncDate = Date()
            message = L10n.nanoleafAdded(synced.count)
        }
    }

    func removeNanoleafDevice(_ device: NanoleafDevice) async {
        var next = nanoleafSettings
        next.devices.removeAll { $0.id == device.id }
        await runBusy {
            nanoleafSettings = try nanoleafSettingsStore.save(next)
            lightProviders[.nanoleaf] = nil
            let synced = try await syncConfiguredProviders()
            setSyncedLamps(synced)
            selectedLampIds = selectedLampIds.intersection(Set(synced.map(\.id)))
            expandedLampIds = expandedLampIds.intersection(Set(synced.map(\.id)))
            lastSyncDate = Date()
            message = L10n.nanoleafRemoved
        }
    }

    private func loadNanoleafSettings() {
        do { nanoleafSettings = try nanoleafSettingsStore.load() } catch { }
    }

    // MARK: - WiZ

    func addWizDevice(host: String, name: String) async {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty else { showError(L10n.wizIPRequired); return }

        let device = WizDevice(name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? cleanHost : name.trimmingCharacters(in: .whitespacesAndNewlines),
                               host: cleanHost)
        var next = wizSettings
        next.devices.append(device)

        await runBusy {
            wizSettings = try wizSettingsStore.save(next)
            lightProviders[.wiz] = nil
            let synced = try await syncConfiguredProviders()
            setSyncedLamps(synced)
            selectedLampIds = selectedLampIds.intersection(Set(synced.map(\.id)))
            expandedLampIds = expandedLampIds.intersection(Set(synced.map(\.id)))
            lastSyncDate = Date()
            message = L10n.wizAdded(synced.count)
        }
    }

    func removeWizDevice(_ device: WizDevice) async {
        var next = wizSettings
        next.devices.removeAll { $0.id == device.id }
        await runBusy {
            wizSettings = try wizSettingsStore.save(next)
            lightProviders[.wiz] = nil
            let synced = try await syncConfiguredProviders()
            setSyncedLamps(synced)
            selectedLampIds = selectedLampIds.intersection(Set(synced.map(\.id)))
            expandedLampIds = expandedLampIds.intersection(Set(synced.map(\.id)))
            lastSyncDate = Date()
            message = L10n.wizRemoved
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
            case .applySceneFocus: await applyPreset(id: "focus", byUser: true)
            case .applySceneRelax: await applyPreset(id: "relax", byUser: true)
            case .applySceneNeon:  await applyPreset(id: "neon",  byUser: true)
            case .applySceneNight: await applyPreset(id: "night", byUser: true)
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
            message = L10n.allLampsPower(value)
        }
    }

    func saveShortcutSettings() async {
        await runBusy {
            shortcutSettings = try shortcutSettingsStore.save(shortcutSettings)
            message = L10n.shortcutsSaved
        }
        NotificationCenter.default.post(name: .shortcutSettingsDidChange, object: nil)
    }

    private func loadShortcutSettings() {
        shortcutSettings = (try? shortcutSettingsStore.load()) ?? .default
    }

    // MARK: - Automations

    func saveAutomation(_ automation: Automation) {
        guard licenseState.entitlements.canUseAutomations else {
            message = L10n.premiumAutomations
            return
        }
        if let idx = automations.firstIndex(where: { $0.id == automation.id }) {
            automations[idx] = automation
        } else {
            automations.append(automation)
        }
        try? automationStore.save(automations)
        automationScheduler.update(automations: automations)
        message = L10n.automationSaved(automation.name)
    }

    func deleteAutomation(_ automation: Automation) {
        automations.removeAll { $0.id == automation.id }
        try? automationStore.save(automations)
        automationScheduler.update(automations: automations)
        message = L10n.automationDeleted
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
            Task { await self.executeAutomationAction(automation.action) }
        }
        automationScheduler.start(with: automations)
    }

    private func loadAutomations() {
        automations = (try? automationStore.load()) ?? []
    }

    // MARK: - Adaptive Lighting

    /// Turns adaptive lighting off before a user-picked scene and remembers
    /// to say so in the scene's confirmation message.
    private func pauseAdaptiveForScene() async {
        guard circadianSettings.isEnabled else { return }
        await setAdaptiveLighting(enabled: false)
        pendingAdaptiveNotice = true
    }

    func setAdaptiveLighting(enabled: Bool) async {
        guard licenseState.entitlements.canUseAdaptiveLighting || !enabled else {
            message = L10n.premiumAdaptive
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
            message = L10n.adaptiveSaved
        }
    }

    func applyCircadianNow() async {
        guard circadianSettings.isEnabled else { return }
        let (brightness, temperature) = circadianService.currentValues()
        // Only adjust lamps that are already on: adaptive lighting must not
        // switch lamps on, and bulbs reject CT/brightness while off anyway.
        let targets = lamps.filter { $0.online && $0.power }
        guard !targets.isEmpty else { return }
        // Runs every 15 min in the background: no busy state and no banner,
        // which used to dim the UI and resize the popover on every tick.
        for lamp in targets {
            guard let provider = try? makeLightProvider(for: lamp) else { continue }
            // Providers take each lamp's native range: convert from % / Kelvin.
            if circadianSettings.applyBrightness, let capability = lamp.capabilities.brightness,
               let updated = try? await provider.setBrightness(
                   deviceId: lamp.nativeID,
                   value: LampScale.nativeBrightness(percent: brightness, capability: capability)) {
                updateLamp(updated)
            }
            if circadianSettings.applyTemperature, let capability = lamp.capabilities.temperature,
               let updated = try? await provider.setTemperature(
                   deviceId: lamp.nativeID,
                   value: LampScale.nativeTemperature(kelvin: temperature, capability: capability)) {
                updateLamp(updated)
            }
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
            seedPresetScenesIfNeeded()
        } catch {
            showError(L10n.scenesUnreadable)
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
                        self.showError(L10n.licenseNotValidated)
                    }
                }
            }
        } catch {
            licenseState = .earlyAccess
            showError(L10n.licenseUnreadable)
        }
    }

    /// Settings › "Restore default scenes": re-adds missing built-ins and
    /// resets modified ones; the user's own scenes are untouched.
    func restoreDefaultScenes() {
        userScenes = PresetScenes.restored(userScenes)
        UserDefaults.standard.set(true, forKey: PresetScenes.seededDefaultsKey)
        persistScenes()
        persistWidgetSnapshot()
        message = L10n.scenesRestored
    }

    // MARK: - Reset all settings

    /// Wipes every persisted setting (see `AppResetService`) except the license,
    /// then relaunches the app.
    ///
    /// Relaunch instead of an in-process reload: state lives in ~15 `@Published`
    /// properties, per-provider clients, the shortcut registrations, the
    /// automation / circadian timers, Yeelight sockets and Sparkle's cached
    /// preferences. Re-initialising all of that in place is easy to get subtly
    /// wrong (a stale timer or secret would survive); a fresh process reads the
    /// now-empty stores and goes through the normal first-launch path
    /// (seeding presets, onboarding) with nothing left to forget.
    func resetAllSettings() {
        isResettingApp = true
        autoSyncTask?.cancel()
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
    /// would otherwise just re-activate the running one.
    private func relaunchApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
        }
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

    // MARK: - Yeelight live sync (push notifications)

    private func configureYeelightLiveSync() {
        yeelightLiveSync.onUpdate = { [weak self] bulb, properties, online in
            self?.applyYeelightLiveState(bulb: bulb, properties: properties, online: online)
        }
        yeelightLiveSync.onRepeatedFailure = { [weak self] _ in
            Task { @MainActor in await self?.recoverYeelightAddressesIfNeeded() }
        }

        // Sockets die with the process anyway; closing them politely frees the bulb's
        // (max 4) connection slots immediately.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.yeelightLiveSync.stopAll() }
        }
        // Connections silently go stale across sleep.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.yeelightLiveSync.reconnectAll() }
        }
    }

    private func scheduleYeelightRecovery() {
        guard yeelightSettings.isConfigured else { return }
        Task { await recoverYeelightAddressesIfNeeded() }
    }

    /// Starts/stops/re-points one listener per configured bulb.
    private func reconcileYeelightLiveSync() {
        yeelightLiveSync.reconcile(bulbs: yeelightSettings.bulbs)
    }

    /// Maps a pushed (or merged) property set onto the matching lamp with the exact same
    /// function the polling path uses, publishing only when something actually changed.
    private func applyYeelightLiveState(bulb: YeelightBulb, properties: [String: String], online: Bool) {
        let next = YeelightLightProvider.makeLamp(bulb: bulb, properties: properties, online: online)
        guard let current = lamps.first(where: { $0.id == next.id }), current != next else { return }
        // A push describing an older state than the user's latest value (echo of an earlier
        // command, a smooth transition's intermediate step) must not move their slider back.
        // The live-sync keeps the latest properties; they are applied when the window closes.
        if online, isHolding(next.id) { return }
        (lightProviders[.yeelight] as? YeelightLightProvider)?.noteExternalState(next)
        updateLamp(next)
    }

    /// Stores a freshly polled lamp list, layering the (newer) live Yeelight state on top and
    /// avoiding a SwiftUI publish when nothing changed.
    private func setSyncedLamps(_ synced: [LampDevice]) {
        let merged = synced.map { lamp -> LampDevice in
            guard lamp.providerID == .yeelight,
                  let bulb = yeelightSettings.bulbs.first(where: { $0.id == lamp.nativeID }),
                  let live = yeelightLiveSync.liveProperties(for: bulb.id)
            else { return lamp }
            return YeelightLightProvider.makeLamp(bulb: bulb, properties: live, online: true)
        }
        // A poll that was already running when the user started adjusting a lamp returns the
        // state from before their value: keep what is on screen for lamps being adjusted.
        let now = Date()
        let guarded = merged.map { lamp -> LampDevice in
            LampInteractionGuard.resolve(
                incoming: lamp,
                current: lamps.first { $0.id == lamp.id },
                holding: interactionGuard.isHolding(lamp.id, now: now, commandsPending: !commandQueue.isIdle(lamp.id)))
        }
        if lamps != guarded { lamps = guarded }
    }

    // MARK: - Yeelight discovery & IP following

    /// User-triggered network search from Settings.
    func searchYeelightBulbs() async {
        guard !isSearchingYeelight else { return }
        isSearchingYeelight = true
        defer { isSearchingYeelight = false }

        do {
            let found = try await YeelightDiscovery.search()
            lastYeelightDiscovery = Date()
            discoveredYeelightBulbs = found
            yeelightSearchCompleted = true
            await applyYeelightDiscovery(found)
        } catch {
            discoveredYeelightBulbs = []
            yeelightSearchCompleted = false
            showError(error)
        }
    }

    func addDiscoveredYeelightBulb(_ found: YeelightDiscoveredBulb) async {
        await addYeelightBulb(host: found.address, name: found.displayName, deviceId: found.id)
    }

    func isYeelightBulbAdded(_ found: YeelightDiscoveredBulb) -> Bool {
        yeelightSettings.bulbs.contains { $0.deviceId == found.id || ($0.host == found.host && $0.port == found.port) }
    }

    /// Background recovery: when a bulb is unreachable (poll or listener failures), or some
    /// bulbs still lack a device id, run a rate-limited discovery and follow address changes.
    func recoverYeelightAddressesIfNeeded() async {
        guard yeelightSettings.isConfigured, !isRecoveringYeelight, !isSearchingYeelight else { return }

        let unreachableNativeIDs = Set(lamps.filter { $0.providerID == .yeelight && !$0.online }.map(\.nativeID))
        let needsRecovery = yeelightSettings.bulbs.contains { bulb in
            bulb.deviceId == nil || unreachableNativeIDs.contains(bulb.id)
        }
        guard needsRecovery else { return }

        if let last = lastYeelightDiscovery, Date().timeIntervalSince(last) < yeelightDiscoveryInterval { return }
        lastYeelightDiscovery = Date()
        isRecoveringYeelight = true
        defer { isRecoveringYeelight = false }

        guard let found = try? await YeelightDiscovery.search() else { return }
        if await applyYeelightDiscovery(found) {
            // A bulb moved: retry the poll against the new address.
            await syncLamps(silent: true)
        }
    }

    /// Backfills missing device ids for bulbs seen at their known host and follows bulbs whose
    /// known device id now answers from a different address. Persists any change and restarts
    /// the affected listeners. Returns true when an address changed.
    @discardableResult
    private func applyYeelightDiscovery(_ found: [YeelightDiscoveredBulb]) async -> Bool {
        var next = yeelightSettings
        var changed = false
        var moved = false

        for index in next.bulbs.indices {
            let bulb = next.bulbs[index]
            if let deviceId = bulb.deviceId {
                if let match = found.first(where: { $0.id == deviceId }),
                   match.host != bulb.host || match.port != bulb.port {
                    next.bulbs[index].host = match.host
                    next.bulbs[index].port = match.port
                    changed = true
                    moved = true
                }
            } else if let match = found.first(where: { $0.host == bulb.host }),
                      !next.bulbs.contains(where: { $0.deviceId == match.id }) {
                next.bulbs[index].deviceId = match.id
                changed = true
            }
        }

        guard changed else { return false }
        do {
            yeelightSettings = try yeelightSettingsStore.save(next)
        } catch {
            return false
        }
        lightProviders[.yeelight] = nil
        reconcileYeelightLiveSync()
        return moved
    }

    private func updateLamp(_ next: LampDevice) {
        guard let index = lamps.firstIndex(where: { $0.id == next.id }) else { return }
        let previous = lamps[index]
        // Publishing an identical lamp still re-rendered the whole popover (every command
        // result and push echo repeats the optimistic value): skip no-ops.
        guard previous != next else { return }
        lamps[index] = next
        // The snapshot only holds counts; writing it on every slider tick
        // (previews call this continuously) was needless disk I/O.
        if previous.power != next.power || previous.online != next.online {
            persistWidgetSnapshot()
        }
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
        // The previous message is kept until the operation sets a new one:
        // clearing it first made the banner vanish and reappear on every click
        // (visible flicker).
        isBusy = true
        defer {
            isBusy = false
            pendingAdaptiveNotice = false
        }

        do {
            try await operation()
            if pendingAdaptiveNotice {
                let notice = NSLocalizedString("adaptive.paused.by.scene", comment: "")
                message = message.isEmpty ? notice : "\(message) \(notice)"
            }
        } catch {
            showError(error)
        }
    }

    func showError(_ error: Error) {
        showError(error.localizedDescription)
    }

    func showError(_ text: String) {
        message = text
        messageIsError = true
    }

    private func scheduleMessageDismiss() {
        messageDismissTask?.cancel()
        guard !message.isEmpty else { return }
        let shown = message
        messageDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard let self, !Task.isCancelled, self.message == shown, !self.messageIsError else { return }
            self.message = ""
        }
    }

    private func persistWidgetSnapshot() {
        guard !isResettingApp else { return }
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
