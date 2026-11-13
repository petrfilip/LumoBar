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
    @Published var isBusy = false
    @Published var hasSecret = false
    @Published var selectedLampIds = Set<String>()
    @Published var groupColor = HSVColor.warm
    @Published var lastSyncDate: Date?
    @Published var isAutoSyncing = false
    @Published var isGroupPanelExpanded = false
    @Published var expandedLampIds = Set<String>()
    @Published var isOnboardingPresented = false
    /// A Settings page to open; consumed (set back to nil) by `SettingsView`.
    @Published var requestedSettingsPage: SettingsPage?
    @Published var userScenes: [UserLightScene] = []
    @Published var hideOfflineLamps = false
    @Published var lampOrderIds: [String] = []
    @Published var searchText = ""
    @Published var rooms: [Room] = []
    /// Rooms the user folded in the lamp list. Persisted: the lamp list is rebuilt on every
    /// Settings <-> Lamps switch, and rooms are expanded unless listed here.
    @Published private(set) var collapsedRoomIds: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "LampControl.rooms.collapsed") ?? [])
    @Published var focusMappings: [FocusMapping] = []
    @Published var currentFocusIdentifier: String?
    @Published var availableFocusModes: [FocusMode] = [
        FocusMode(identifier: "do-not-disturb", displayName: NSLocalizedString("focus.mode.donotdisturb", comment: "")),
        FocusMode(identifier: "focus", displayName: NSLocalizedString("focus.mode.focus", comment: "")),
        FocusMode(identifier: "sleep", displayName: NSLocalizedString("focus.mode.sleep", comment: ""))
    ]

    /// Not `@Published`: it is an `ObservableObject` itself, and a nested one does not forward its
    /// changes. Views that show its state observe it directly (see `UpdateServiceObserver`).
    let updateService = UpdateService()

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
    private let automationStore = AutomationStore()
    private let circadianSettingsStore = CircadianSettingsStore()
    private let automationScheduler = AutomationScheduler()
    let circadianService = CircadianService()
    private let hueClient = HueClient()
    private let sceneStore = LightSceneStore()
    private var lightProviders: [LightProviderKind: any LightProvider] = [:]
    private var autoSyncTask: Task<Void, Never>?
    private var syncFailureTracker = SyncFailureTracker()
    private let yeelightLiveSync = YeelightLiveSync()
    /// Coalesces and paces what sliders / the color picker stream while the user drags.
    private lazy var commandQueue: LampCommandQueue = makeCommandQueue()
    /// Lamps that were off when the user started adjusting their color: the first command
    /// must switch them on (many bulbs reject color commands while off).
    private var lampsNeedingPowerOn = Set<String>()
    /// Last known real state of lamps being adjusted, for undoing a preview whose command failed.
    private var restorePoints = LampRestorePoints()
    /// Keeps the user's value on screen while they adjust a lamp (see `LampInteractionGuard`).
    private var interactionGuard = LampInteractionGuard()
    private var holdExpiryTasks: [String: Task<Void, Never>] = [:]
    private var lastYeelightDiscovery: Date?
    private var isRecoveringYeelight = false
    private let yeelightRecovery = TaskSlot()
    // Concurrency state (see StateConsistency.swift).
    private var busy = BusyCounter()
    /// Bumped by every user operation and settings save; a background poll that started before
    /// the bump is stale when it finishes and is dropped.
    private var syncGeneration = SyncGeneration()
    private let focusSceneTask = TaskSlot()
    private let circadianApplyTask = TaskSlot()
    private let automationTasks = KeyedTasks<UUID>()
    /// True once a sync answered: before that `lamps` is empty and there is nothing to adjust.
    private var hasSyncedOnce = false
    /// Adaptive lighting wanted to apply before the first sync; it is applied right after it.
    private var circadianApplyPending = false
    /// Minimum delay between automatic (background) network searches.
    private let yeelightDiscoveryInterval: TimeInterval = 5 * 60
    private let onboardingDismissedKey = "LampControl.onboarding.dismissed"
    private let collapsedRoomsKey = "LampControl.rooms.collapsed"
    private let roomsMigratedKey = "LampControl.rooms.migrated"
    /// True while "Reset all settings" runs: blocks background persistence so
    /// nothing re-creates the files that were just removed.
    private var isResettingApp = false

    init() {
        configureYeelightLiveSync()
        loadScenes()
        lampOrderIds = settingsStore.loadLampOrder()
        Task { await runStartupSequence() }
    }

    /// The one place that orders launch: settings and data load first, then the first sync, and
    /// only then the services that act on that data (auto-sync, Yeelight listeners, the
    /// automation scheduler, adaptive lighting). `AppDelegate` starts none of them itself.
    private func runStartupSequence() async {
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

    func loadRoomsAndMigrateIfNeeded() async {
        let defaults = UserDefaults.standard
        let loadedRooms: [Room]
        do {
            loadedRooms = try roomStore.loadRooms()
        } catch {
            // Neither read nor moved aside: keep the file as it is and do not run the migration,
            // which would write a fresh rooms.json over it.
            showError(L10n.dataReadFailed("rooms.json"))
            return
        }
        let plan = RoomLayout.migrationPlan(
            loaded: loadedRooms,
            hasRoomsFile: roomStore.hasRoomsFile,
            alreadyMigrated: defaults.bool(forKey: roomsMigratedKey),
            lampIds: lamps.map(\.id),
            defaultRoomName: NSLocalizedString("rooms.default.name", comment: ""))
        rooms = plan.rooms
        if plan.persist {
            do {
                try roomStore.saveRooms(rooms)
            } catch {
                showError(L10n.roomsSaveFailed)
                return
            }
        }
        if plan.markMigrated && !isResettingApp { defaults.set(true, forKey: roomsMigratedKey) }
    }

    func isRoomExpanded(_ roomId: String) -> Bool {
        !collapsedRoomIds.contains(roomId)
    }

    func toggleRoomExpanded(_ roomId: String) {
        if collapsedRoomIds.contains(roomId) {
            collapsedRoomIds.remove(roomId)
        } else {
            collapsedRoomIds.insert(roomId)
        }
        guard !isResettingApp else { return }
        UserDefaults.standard.set(Array(collapsedRoomIds).sorted(), forKey: collapsedRoomsKey)
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

    func addRoom(name: String) {
        rooms.append(Room(name: name))
        persistRooms()
    }

    func renameRoom(_ roomId: String, to name: String) {
        guard let index = rooms.firstIndex(where: { $0.id == roomId }) else { return }
        rooms[index].name = name
        persistRooms()
    }

    func deleteRoom(_ roomId: String) {
        rooms.removeAll { $0.id == roomId }
        persistRooms()
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
            try await setPower(value, on: targets)
            message = L10n.roomPower(value)
        }
    }

    func applyScene(_ scene: UserLightScene, toRoomId roomId: String, byUser: Bool = false) async {
        guard let room = rooms.first(where: { $0.id == roomId }) else { return }
        // A captured scene restores each lamp's own look (white-only lamps included); a plain
        // color scene needs color-capable lamps.
        let targets = lamps.filter {
            room.lampIds.contains($0.id) && $0.online && (scene.isCapture || $0.capabilities.colorCode != nil)
        }
        guard !targets.isEmpty else { showError(scene.isCapture ? L10n.roomNoOnlineLamp : L10n.roomNoOnlineRGB); return }
        let paused = await pauseAdaptiveForScene(byUser: byUser)

        await runBusy(adaptiveNotice: paused) {
            if let snapshots = scene.snapshots {
                let outcome = await restoreSnapshots(snapshots, on: targets)
                for lamp in outcome.updated { updateLamp(lamp) }
                if let error = outcome.firstError { throw error }
                try Task.checkCancellation()
            } else {
                try await applyColorToEach(scene.color, on: targets)
            }
            message = L10n.roomSceneApplied(scene.title)
        }
    }

    /// Brings each of `candidates` to its captured snapshot (see `LampSnapshot.steps`). A lamp
    /// that fails does not stop the others, and what changed before a failure is kept so the UI
    /// shows the real state; only the first error is returned, to be reported once.
    private func restoreSnapshots(_ snapshots: [LampSnapshot], on candidates: [LampDevice])
        async -> (updated: [LampDevice], firstError: Error?) {
        var updated: [LampDevice] = []
        var firstError: Error?
        for snap in snapshots {
            guard !Task.isCancelled else { break }
            guard let lamp = candidates.first(where: { $0.id == snap.lampId && $0.online }) else { continue }
            noteUserActivity(lamp.id)
            var latest: LampDevice?
            do {
                let provider = try makeLightProvider(for: lamp)
                for step in snap.steps(for: lamp) {
                    switch step {
                    case .power(let on): latest = try await provider.setPower(deviceId: lamp.nativeID, value: on)
                    case .temperature(let v): latest = try await provider.setTemperature(deviceId: lamp.nativeID, value: v)
                    case .brightness(let v): latest = try await provider.setBrightness(deviceId: lamp.nativeID, value: v)
                    case .color(let c): latest = try await provider.setColor(deviceId: lamp.nativeID, color: c)
                    }
                }
            } catch {
                // A superseded run (cancelled Focus change) stops quietly.
                if Task.isCancelled || error is CancellationError { break }
                if firstError == nil { firstError = error }
            }
            if let latest {
                noteUserActivity(lamp.id)
                updated.append(latest)
            }
        }
        return (updated, firstError)
    }

    // MARK: - Focus Mode Mappings

    func loadFocusMappings() {
        do {
            focusMappings = try focusMappingStore.loadMappings()
        } catch {
            showError(L10n.dataReadFailed("focusMappings.json"))
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
            showError(String(format: NSLocalizedString(key, comment: ""), error.localizedDescription))
        }
        refreshLoginItemStatus()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: Focus automation (URL scheme)

    private static let resetLog = Logger(subsystem: "fr.hugoinformatique.lampcontrol", category: "Reset")
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

    var visibleLamps: [LampDevice] {
        var filtered = lamps

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
            let orderIndex = Dictionary(lampOrderIds.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            filtered.sort { a, b in
                let aIndex = orderIndex[a.id] ?? Int.max
                let bIndex = orderIndex[b.id] ?? Int.max
                return aIndex < bIndex
            }
        }

        return filtered
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
        } catch {
            showError(error)
        }
    }

    /// The credential is passed in by the settings form (which edits a draft): nothing typed
    /// reaches the live settings until it is saved here. Returns true when it was stored.
    @discardableResult
    func saveLifxSettingsAndSync(token: String) async -> Bool {
        var saved = false
        await runBusy {
            lifxSettings = try lifxSettingsStore.save(LifxSettings(token: token))
            saved = true
            lightProviders[.lifx] = nil
            let merged = await syncConfiguredProviders(dropPrevious: [.lifx])
            let synced = applySync(merged)
            finishManualSync(merged, message: L10n.lifxConnected(synced.count), ownedBy: .lifx)
        }
        return saved
    }

    @discardableResult
    func saveGoveeSettingsAndSync(apiKey: String) async -> Bool {
        var saved = false
        await runBusy {
            goveeSettings = try goveeSettingsStore.save(GoveeSettings(apiKey: apiKey))
            saved = true
            lightProviders[.govee] = nil
            let merged = await syncConfiguredProviders(dropPrevious: [.govee])
            let synced = applySync(merged)
            finishManualSync(merged, message: L10n.goveeConnected(synced.count), ownedBy: .govee)
        }
        return saved
    }

    /// Forgets the credential of a cloud / bridge provider (Keychain item included) and drops
    /// its lamps. Device-list providers (Yeelight, WiZ, Nanoleaf) are disconnected by removing
    /// their devices.
    func disconnectProvider(_ kind: LightProviderKind) async {
        await runBusy {
            switch kind {
            case .lifx:
                lifxSettings = try lifxSettingsStore.save(LifxSettings(token: ""))
            case .govee:
                goveeSettings = try goveeSettingsStore.save(GoveeSettings(apiKey: ""))
            case .philipsHue:
                var next = hueSettings
                next.username = ""
                hueSettings = try hueSettingsStore.save(next)
            case .tuya:
                let saved = try settingsStore.save(settings, clearSecret: true)
                settings = saved.settings
                hasSecret = saved.hasSecret
            case .yeelight, .nanoleaf, .wiz:
                return
            }
            lightProviders[kind] = nil
            let merged = await syncConfiguredProviders(dropPrevious: [kind])
            applySync(merged)
            finishManualSync(merged, message: L10n.providerDisconnected(kind.title))
        }
    }

    /// Returns true when the bulb was saved (the form may then be cleared); false when it was
    /// rejected (invalid address, duplicate) or saving failed, after surfacing the reason.
    @discardableResult
    func addYeelightBulb(host: String, name: String, deviceId: String? = nil) async -> Bool {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty else {
            showError(L10n.yeelightIPRequired)
            return false
        }

        let hostOnly: String
        let port: Int
        do {
            (hostOnly, port) = try YeelightAddress.parse(cleanHost)
        } catch {
            showError(error)
            return false
        }

        var next = yeelightSettings
        let normalizedID = deviceId?.lowercased()
        if next.bulbs.contains(where: { existing in
            (normalizedID != nil && existing.deviceId == normalizedID) || (existing.host == hostOnly && existing.port == port)
        }) {
            showError(L10n.yeelightAlreadyAdded)
            return false
        }
        let bulb = YeelightBulb(host: hostOnly, port: port, name: name.trimmingCharacters(in: .whitespacesAndNewlines), deviceId: deviceId)
        next.bulbs.append(bulb)

        var saved = false
        await runBusy {
            yeelightSettings = try yeelightSettingsStore.save(next)
            saved = true
            lightProviders[.yeelight] = nil
            // Right after the save: a failing unrelated provider in the sync below must not
            // leave the new bulb without its push listener.
            reconcileYeelightLiveSync()
            let merged = await syncConfiguredProviders()
            let synced = applySync(merged)
            finishManualSync(merged, message: L10n.yeelightAdded(synced.count))
        }
        return saved
    }

    func removeYeelightBulb(_ bulb: YeelightBulb) async {
        var next = yeelightSettings
        next.bulbs.removeAll { $0.id == bulb.id }

        await runBusy {
            yeelightSettings = try yeelightSettingsStore.save(next)
            lightProviders[.yeelight] = nil
            reconcileYeelightLiveSync()
            let merged = await syncConfiguredProviders(dropPrevious: [.yeelight])
            applySync(merged)
            finishManualSync(merged, message: L10n.yeelightRemoved)
        }
    }

    /// `draft` comes from the settings form; an empty `accessSecret` keeps the stored secret.
    @discardableResult
    func saveSettings(_ draft: TuyaSettings) async -> Bool {
        var stored = false
        await runBusy {
            let saved = try settingsStore.save(draft)
            settings = saved.settings
            hasSecret = saved.hasSecret
            stored = true
            lightProviders[.tuya] = nil
            message = L10n.settingsSaved
            selectedTab = .lamps
        }
        return stored
    }

    @discardableResult
    func saveSettingsAndSync(_ draft: TuyaSettings) async -> Bool {
        var stored = false
        await runBusy {
            let saved = try settingsStore.save(draft)
            settings = saved.settings
            hasSecret = saved.hasSecret
            stored = true
            lightProviders[.tuya] = nil

            let merged = await syncConfiguredProviders(dropPrevious: [.tuya])
            let synced = applySync(merged)
            finishManualSync(merged, message: synced.isEmpty ? L10n.settingsSavedNoneFound : L10n.lampsSynced(synced.count), ownedBy: .tuya)
        }
        return stored
    }

    func syncLamps(silent: Bool = false) async {
        guard canSync else { return }

        if silent {
            guard !isBusy && !isAutoSyncing else { return }
            // Don't poll bulbs while the user is adjusting one: the reply would be stale on arrival.
            guard !interactionGuard.isAnyHolding(now: Date()), commandQueue.isAllIdle else { return }
            isAutoSyncing = true
            defer { isAutoSyncing = false }

            let generation = syncGeneration.value
            let merged = await syncConfiguredProviders()
            // The user acted (or settings changed) while the providers were answering: this
            // result describes the state from before, and would revert their change in the UI
            // or bring back a device they just removed. The next poll starts fresh.
            guard syncGeneration.isCurrent(generation) else { return }
            applySync(merged)
            reportSyncFailures(merged, silent: true)
            if merged.didSync {
                persistWidgetSnapshot()
                scheduleYeelightRecovery()
            }

            return
        }

        await runBusy {
            let merged = await syncConfiguredProviders()
            let synced = applySync(merged)
            finishManualSync(merged, message: synced.isEmpty ? L10n.lampsNoneFound : L10n.lampsSynced(synced.count))
            persistWidgetSnapshot()
            scheduleYeelightRecovery()
        }
    }

    func toggle(_ lamp: LampDevice) async -> Bool {
        // A poll already in flight describes the lamp from before this click: hold the lamp
        // (and drop that poll) so the new state is not reverted until the lamp has answered.
        syncGeneration.bump()
        noteUserActivity(lamp.id)
        updateLamp(lamp.withPower(!lamp.power))

        do {
            let updated = try await makeLightProvider(for: lamp).setPower(deviceId: lamp.nativeID, value: !lamp.power)
            noteUserActivity(lamp.id)
            updateLamp(updated)
            return true
        } catch {
            noteUserActivity(lamp.id)
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
        prepareAdjustment(of: lamp)
        updateLamp(lamp.withBrightness(value).withPower(true))
        enqueue(.brightness(value), for: lamp, isFinal: false)
    }

    func commitBrightness(_ lamp: LampDevice, value: Int) async {
        endUserActivity(lamp.id)
        prepareAdjustment(of: lamp)
        enqueue(.brightness(value), for: lamp, isFinal: true)
    }

    func previewTemperature(_ lamp: LampDevice, value: Int) {
        noteUserActivity(lamp.id)
        prepareAdjustment(of: lamp)
        updateLamp(lamp.withTemperature(value))
        enqueue(.temperature(value), for: lamp, isFinal: false)
    }

    func commitTemperature(_ lamp: LampDevice, value: Int) async {
        endUserActivity(lamp.id)
        prepareAdjustment(of: lamp)
        enqueue(.temperature(value), for: lamp, isFinal: true)
    }

    func previewColor(_ lamp: LampDevice, color: HSVColor) {
        noteUserActivity(lamp.id)
        prepareAdjustment(of: lamp)
        updateLamp(lamp.previewingColor(color).withPower(true))
        enqueue(.color(color), for: lamp, isFinal: false)
    }

    func commitColor(_ lamp: LampDevice, color: HSVColor) async {
        endUserActivity(lamp.id)
        prepareAdjustment(of: lamp)
        enqueue(.color(color), for: lamp, isFinal: true)
    }

    /// Runs before every preview / commit: remembers the real state to fall back to if the
    /// command fails, and flags a lamp that is off so the first command switches it on (bulbs
    /// such as Yeelight reject color / temperature / brightness while off). The state is read
    /// from `lamps`, not from `lamp`: after the first preview the UI already shows it as on.
    private func prepareAdjustment(of lamp: LampDevice) {
        let current = lamps.first { $0.id == lamp.id } ?? lamp
        restorePoints.remember(current)
        if !current.power { lampsNeedingPowerOn.insert(lamp.id) }
    }

    /// A command failed: stop showing the unapplied preview. Bulbs that push their state
    /// (Yeelight) go back to the live one, the others to the state from before the adjustment.
    private func restoreAfterFailure(_ lampID: String) {
        lampsNeedingPowerOn.remove(lampID)
        let restorePoint = restorePoints.take(lampID)
        var live: LampDevice?
        if let lamp = lamps.first(where: { $0.id == lampID }), lamp.providerID == .yeelight,
           let bulb = yeelightSettings.bulbs.first(where: { $0.id == lamp.nativeID }),
           let props = yeelightLiveSync.liveProperties(for: bulb.id) {
            live = YeelightLightProvider.makeLamp(bulb: bulb, properties: props, online: true)
        }
        guard let restored = LampRestorePoints.restoredState(live: live, restorePoint: restorePoint) else { return }
        if live != nil { (lightProviders[.yeelight] as? YeelightLightProvider)?.noteExternalState(restored) }
        updateLamp(restored)
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
    /// Initial cache of a freshly created Yeelight provider. The provider skips commands that
    /// match what its cache says the bulb shows, so the cache must describe the *bulb*, never
    /// the optimistic value on screen: prefer the state the bulb pushed, and leave out lamps the
    /// user is adjusting (their on-screen value has not reached the bulb yet).
    private func yeelightProviderSeed() -> [LampDevice] {
        lamps.compactMap { lamp in
            guard lamp.providerID == .yeelight else { return nil }
            if let bulb = yeelightSettings.bulbs.first(where: { $0.id == lamp.nativeID }),
               let live = yeelightLiveSync.liveProperties(for: bulb.id) {
                return YeelightLightProvider.makeLamp(bulb: bulb, properties: live, online: true)
            }
            return isHolding(lamp.id) ? nil : lamp
        }
    }

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
            self.restorePoints.confirm(lamp)
            self.updateLamp(lamp)
        }
        queue.onIdle = { [weak self] lampID in
            guard let self else { return }
            self.restorePoints.discard(lampID)
            // The grace period counts from the last command's reply.
            self.interactionGuard.touch(lampID, now: Date())
            self.scheduleHoldExpiry(for: lampID)
        }
        queue.onFailure = { [weak self] lampID, error in
            guard let self else { return }
            self.restoreAfterFailure(lampID)
            self.showError(error)
        }
        return queue
    }

    private func perform(_ command: LampCommand, lampID: String, transition: TimeInterval) async throws -> LampDevice? {
        guard var lamp = lamps.first(where: { $0.id == lampID }) else { return nil }
        // The UI already shows the lamp as on; the bulb may still be off.
        let wasOff = lampsNeedingPowerOn.remove(lampID) != nil
        if wasOff { lamp.power = false }
        let provider = try makeLightProvider(for: lamp)
        switch command {
        case .brightness(let value):
            if wasOff { _ = try await provider.setPower(deviceId: lamp.nativeID, value: true) }
            return try await provider.setBrightness(deviceId: lamp.nativeID, value: value, transition: transition)
        case .temperature(let value):
            if wasOff { _ = try await provider.setPower(deviceId: lamp.nativeID, value: true) }
            return try await provider.setTemperature(deviceId: lamp.nativeID, value: value, transition: transition)
        case .color(let color):
            return try await applyColor(color, to: lamp, transition: transition)
        }
    }

    func toggleSelection(_ lamp: LampDevice) {
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

        // Reserve room for every visible lamp row (expanded rows at their full
        // height) + room headers. Previously capped at 3 rows / 620 pt, so two
        // expanded lamps already did not fit; the screen height is the real
        // limit (see preferredPopoverHeight), the ScrollView absorbs the rest.
        // Lamps inside a collapsed room are not shown: only their room header counts.
        let hiddenByCollapse = RoomLayout.lampIdsHiddenByCollapse(rooms: rooms, collapsedRoomIds: collapsedRoomIds)
        for lamp in visibleLamps where !hiddenByCollapse.contains(lamp.id) {
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
        persistWidgetSnapshot()

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
        let paused = await pauseAdaptiveForScene(byUser: byUser)

        groupColor = color

        await runBusy(adaptiveNotice: paused) {
            let count = try await applyColorToEach(color, on: targets)
            message = selectedTargets.isEmpty
                ? L10n.ambianceAppliedToAll(title)
                : L10n.ambianceApplied(title, count: count)
        }
    }

    func applyGroupPower(_ value: Bool) async {
        guard lamps.contains(where: { selectedLampIds.contains($0.id) }) else {
            showError(L10n.selectLamp)
            return
        }
        // Offline lamps cannot answer: skip them instead of failing the whole group.
        let targets = lamps.filter { selectedLampIds.contains($0.id) && $0.online }
        guard !targets.isEmpty else {
            showError(L10n.roomNoOnlineLamp)
            return
        }

        await runBusy {
            try await setPower(value, on: targets)
            message = L10n.groupPower(value)
        }
    }

    func discoverHueBridges() async {
        await runBusy {
            discoveredHueBridges = try await hueClient.discoverBridges()
            message = discoveredHueBridges.isEmpty ? L10n.hueNoneFound : L10n.hueBridgesFound(discoveredHueBridges.count)
        }
    }

    /// Pairs with the bridge at `bridgeIP` (the user pressed its button) and saves the result.
    /// The address comes from the settings form's draft; it only becomes part of the live
    /// settings once pairing worked. Returns true when the bridge was paired and stored.
    @discardableResult
    func pairHueBridge(bridgeID: String, bridgeIP: String) async -> Bool {
        var paired = false
        await runBusy {
            let ip = bridgeIP.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ip.isEmpty else {
                throw LampControlError.configuration(L10n.hueBridgeRequired)
            }

            let username = try await hueClient.createUser(bridgeIP: ip)
            guard !isResettingApp else { return }
            hueSettings = try hueSettingsStore.save(HueSettings(bridgeID: bridgeID, bridgeIP: ip, username: username))
            paired = true
            lightProviders[.philipsHue] = nil
            message = L10n.hueBridgeConnected
        }
        return paired
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

    // MARK: - Multi-lamp actions

    /// Switches every lamp of `targets`. A failing lamp does not stop the others; what worked is
    /// shown, then the first error is thrown (see `BulkLampAction`).
    @discardableResult
    private func setPower(_ value: Bool, on targets: [LampDevice]) async throws -> Int {
        try await applyToEach(targets) { lamp in
            try await self.makeLightProvider(for: lamp).setPower(deviceId: lamp.nativeID, value: value)
        }
    }

    @discardableResult
    private func applyColorToEach(_ color: HSVColor, on targets: [LampDevice]) async throws -> Int {
        try await applyToEach(targets) { lamp in try await self.applyColor(color, to: lamp) }
    }

    private func applyToEach(_ targets: [LampDevice], _ operation: (LampDevice) async throws -> LampDevice) async throws -> Int {
        // Hold every target while the action runs, so a poll answering in between does not
        // put the old state back on a lamp that was already updated.
        for lamp in targets { noteUserActivity(lamp.id) }
        let outcome = await BulkLampAction.run(on: targets, operation: operation, onUpdate: { updated in
            noteUserActivity(updated.id)
            updateLamp(updated)
        })
        if let error = outcome.firstError { throw error }
        if outcome.wasCancelled { throw CancellationError() }
        return outcome.updatedCount
    }

    /// Closes the menu-bar popover without quitting. Set by `AppDelegate`.
    var closePopover: (() -> Void)?

    func quit() {
        yeelightLiveSync.stopAll()
        NSApplication.shared.terminate(nil)
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

    /// Syncs every configured provider independently and concurrently. A provider that fails
    /// keeps its previous lamps (marked offline) and is reported in `failures`; it never drops
    /// the other providers' lamps. Never throws.
    private func syncConfiguredProviders(dropPrevious: Set<LightProviderKind> = []) async -> ProviderSyncMerge {
        var results: [ProviderSyncResult] = []
        var runnable: [(kind: LightProviderKind, provider: any LightProvider)] = []
        for kind in configuredProviderKinds {
            do {
                runnable.append((kind, try makeLightProvider(for: kind)))
            } catch {
                results.append(ProviderSyncResult(kind: kind, outcome: .failure(error)))
            }
        }
        await withTaskGroup(of: ProviderSyncResult.self) { group in
            for (kind, provider) in runnable {
                group.addTask {
                    do {
                        return ProviderSyncResult(kind: kind, outcome: .success(try await provider.syncLights()))
                    } catch {
                        return ProviderSyncResult(kind: kind, outcome: .failure(error))
                    }
                }
            }
            for await result in group { results.append(result) }
        }
        return ProviderSyncMerge.merge(previous: lamps, results: results, dropPrevious: dropPrevious)
    }

    /// Publishes a finished sync: the lamp list, the selections that still apply and the sync time.
    /// Every property is assigned only when its value changed: each assignment makes SwiftUI
    /// re-render the popover, and a background poll usually finds nothing new.
    @discardableResult
    private func applySync(_ merged: ProviderSyncMerge) -> [LampDevice] {
        setSyncedLamps(merged.lamps)
        let ids = Set(merged.lamps.map(\.id))
        let selected = selectedLampIds.intersection(ids)
        if selected != selectedLampIds { selectedLampIds = selected }
        let expanded = expandedLampIds.intersection(ids)
        if expanded != expandedLampIds { expandedLampIds = expanded }
        if merged.didSync {
            let now = Date()
            // The status line shows the time to the minute: a newer second changes nothing visible.
            let isNewMinute = lastSyncDate.map { !Calendar.current.isDate($0, equalTo: now, toGranularity: .minute) } ?? true
            if isNewMinute { lastSyncDate = now }
            noteSyncSucceeded()
        }
        return merged.lamps
    }

    private func noteSyncSucceeded() {
        hasSyncedOnce = true
        if circadianApplyPending {
            circadianApplyPending = false
            scheduleCircadianApply()
        }
    }

    /// Ends a manual sync: shows `text`, then any provider failures (which replace it, so the
    /// working providers still appear in the list but the problem is not hidden). `kind` is the
    /// provider the user just set up; the view only moves on to the lamp list when it answered.
    private func finishManualSync(_ merged: ProviderSyncMerge, message text: String, ownedBy kind: LightProviderKind? = nil) {
        message = text
        reportSyncFailures(merged, silent: false)
        if let kind, !merged.failedKinds.contains(kind) { selectedTab = .lamps }
    }

    /// Shows what went wrong during a sync without hiding the providers that worked. A silent
    /// background poll announces each failing provider once until it recovers.
    private func reportSyncFailures(_ merged: ProviderSyncMerge, silent: Bool) {
        var failures = merged.failures
        if silent {
            // A background poll must not talk over an error the user has not seen yet (a data
            // recovery notice, a failed save). Nothing is marked as reported, so a provider that
            // is still failing is announced by a later poll, once the banner has moved on.
            if messageIsError && !message.isEmpty { return }
            let fresh = syncFailureTracker.newlyFailed(merged.failedKinds)
            failures = failures.filter { fresh.contains($0.kind) }
        } else {
            _ = syncFailureTracker.newlyFailed(merged.failedKinds)
        }
        guard !failures.isEmpty else { return }
        showError(failures
            .map { L10n.providerSyncFailed($0.kind.title, detail: $0.error.localizedDescription) }
            .joined(separator: "\n"))
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
            // Bulbs with a connected push listener are not polled (`get_prop`) on top of that.
            provider = YeelightLightProvider(
                settings: yeelightSettings,
                initialLamps: yeelightProviderSeed(),
                liveState: { [weak self] bulbID in self?.yeelightLiveSync.liveProperties(for: bulbID) })
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

    /// Returns true when the device was paired and saved (the form may then be cleared); false
    /// when it was rejected (missing address, duplicate) or failed, after surfacing the reason.
    @discardableResult
    func addNanoleafDevice(host: String, name: String) async -> Bool {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty else { showError(L10n.nanoleafIPRequired); return false }
        guard !DeviceHost.isDuplicate(cleanHost, among: nanoleafSettings.devices.map(\.host)) else {
            showError(L10n.nanoleafAlreadyAdded)
            return false
        }

        var saved = false
        await runBusy {
            let client = NanoleafClient()
            let token = try await client.pairDevice(host: cleanHost)
            let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let device = NanoleafDevice(name: cleanName.isEmpty ? cleanHost : cleanName, host: cleanHost, authToken: token)
            var next = nanoleafSettings
            next.devices.append(device)
            nanoleafSettings = try nanoleafSettingsStore.save(next)
            saved = true
            lightProviders[.nanoleaf] = nil
            let merged = await syncConfiguredProviders()
            let synced = applySync(merged)
            finishManualSync(merged, message: L10n.nanoleafAdded(synced.count))
        }
        return saved
    }

    func removeNanoleafDevice(_ device: NanoleafDevice) async {
        var next = nanoleafSettings
        next.devices.removeAll { $0.id == device.id }
        await runBusy {
            nanoleafSettings = try nanoleafSettingsStore.save(next)
            lightProviders[.nanoleaf] = nil
            let merged = await syncConfiguredProviders(dropPrevious: [.nanoleaf])
            applySync(merged)
            finishManualSync(merged, message: L10n.nanoleafRemoved)
        }
    }

    private func loadNanoleafSettings() {
        do { nanoleafSettings = try nanoleafSettingsStore.load() } catch {
            showError(L10n.settingsUnreadable("Nanoleaf"))
        }
    }

    // MARK: - WiZ

    /// Returns true when the device was saved (the form may then be cleared); false when it was
    /// rejected (missing address, duplicate) or saving failed, after surfacing the reason.
    @discardableResult
    func addWizDevice(host: String, name: String) async -> Bool {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty else { showError(L10n.wizIPRequired); return false }
        guard !DeviceHost.isDuplicate(cleanHost, among: wizSettings.devices.map(\.host)) else {
            showError(L10n.wizAlreadyAdded)
            return false
        }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let device = WizDevice(name: cleanName.isEmpty ? cleanHost : cleanName, host: cleanHost)
        var next = wizSettings
        next.devices.append(device)

        var saved = false
        await runBusy {
            wizSettings = try wizSettingsStore.save(next)
            saved = true
            lightProviders[.wiz] = nil
            let merged = await syncConfiguredProviders()
            let synced = applySync(merged)
            finishManualSync(merged, message: L10n.wizAdded(synced.count))
        }
        return saved
    }

    func removeWizDevice(_ device: WizDevice) async {
        var next = wizSettings
        next.devices.removeAll { $0.id == device.id }
        await runBusy {
            wizSettings = try wizSettingsStore.save(next)
            lightProviders[.wiz] = nil
            let merged = await syncConfiguredProviders(dropPrevious: [.wiz])
            applySync(merged)
            finishManualSync(merged, message: L10n.wizRemoved)
        }
    }

    private func loadWizSettings() {
        do { wizSettings = try wizSettingsStore.load() } catch {
            showError(L10n.settingsUnreadable("WiZ"))
        }
    }

    // MARK: - Power all

    func applyPowerAll(_ value: Bool) async {
        let targets = lamps.filter { $0.online }
        guard !targets.isEmpty else { return }
        await runBusy {
            try await setPower(value, on: targets)
            message = L10n.allLampsPower(value)
        }
    }

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
    private func persistAutomations() -> Bool {
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

    private func startAutomationScheduler() {
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

    private func loadAutomations() {
        do {
            automations = try automationStore.load()
        } catch {
            showError(L10n.dataReadFailed("automations.json"))
        }
    }

    // MARK: - Adaptive Lighting

    /// Turns adaptive lighting off before a user-picked scene. Returns true when it was on, so
    /// the caller can have its own confirmation message say so (`runBusy(adaptiveNotice:)`).
    private func pauseAdaptiveForScene(byUser: Bool) async -> Bool {
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

    private func scheduleCircadianApply() {
        circadianApplyTask.replace { [weak self] in await self?.applyCircadianNow() }
    }

    private func startCircadianService() {
        circadianService.onApply = { [weak self] _, _ in
            self?.scheduleCircadianApply()
        }
        if circadianSettings.isEnabled {
            circadianService.start(with: circadianSettings)
        }
    }

    private func loadCircadianSettings() {
        do {
            circadianSettings = try circadianSettingsStore.load()
        } catch {
            showError(L10n.dataReadFailed("circadian-settings.json"))
        }
    }

    /// Tells the user, once, about files the stores had to set aside while loading (see
    /// `JSONFileStore` for the policy).
    private func reportDataRecoveries() {
        let events = RecoveryLog.shared.drain()
        guard !events.isEmpty else { return }
        showError(L10n.dataRecovered(events))
    }

    private func presentOnboardingIfNeeded() {
        isOnboardingPresented = OnboardingPolicy.shouldPresent(
            hasConfiguredProvider: canSync,
            dismissed: UserDefaults.standard.bool(forKey: onboardingDismissedKey))
    }

    private func loadScenes() {
        do {
            userScenes = try sceneStore.load()
            seedPresetScenesIfNeeded()
        } catch {
            showError(L10n.scenesUnreadable)
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
            guard let self else { return }
            self.scheduleYeelightRecovery()
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

    /// A recovery that is already running is left to finish rather than replaced: the search is
    /// rate-limited and not cancellable, so aborting it for the next poll would only discard
    /// what it found.
    private func scheduleYeelightRecovery() {
        guard yeelightSettings.isConfigured else { return }
        yeelightRecovery.startIfIdle { [weak self] in await self?.recoverYeelightAddressesIfNeeded() }
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
            guard !isResettingApp else { return }
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
        guard !isResettingApp, yeelightSettings.isConfigured, !isRecoveringYeelight, !isSearchingYeelight else { return }

        let unreachableNativeIDs = Set(lamps.filter { $0.providerID == .yeelight && !$0.online }.map(\.nativeID))
        let needsRecovery = yeelightSettings.bulbs.contains { bulb in
            bulb.deviceId == nil || unreachableNativeIDs.contains(bulb.id)
        }
        guard needsRecovery else { return }

        if let last = lastYeelightDiscovery, Date().timeIntervalSince(last) < yeelightDiscoveryInterval { return }
        lastYeelightDiscovery = Date()
        isRecoveringYeelight = true
        defer { isRecoveringYeelight = false }

        guard let found = try? await YeelightDiscovery.search(), !Task.isCancelled, !isResettingApp else { return }
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
        // A search that was in flight when "reset all settings" ran must not rewrite the wiped file.
        guard !isResettingApp else { return false }
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

    /// Runs a user operation with the busy state on. Re-entrant: `isBusy` stays on until the last
    /// of the overlapping operations is done. `adaptiveNotice` belongs to this operation only
    /// (its scene switched adaptive lighting off), so another operation never shows or clears it.
    private func runBusy(adaptiveNotice: Bool = false, _ operation: () async throws -> Void) async {
        // The previous message is kept until the operation sets a new one:
        // clearing it first made the banner vanish and reappear on every click
        // (visible flicker).
        busy.begin()
        if !isBusy { isBusy = true }
        // Whatever poll is in flight describes the state from before this operation.
        syncGeneration.bump()
        defer {
            busy.end()
            if isBusy != busy.isBusy { isBusy = busy.isBusy }
        }

        do {
            try await operation()
            let notice = NSLocalizedString("adaptive.paused.by.scene", comment: "")
            if adaptiveNotice, !messageIsError, !message.contains(notice) {
                message = message.isEmpty ? notice : "\(message) \(notice)"
            }
        } catch is CancellationError {
            // Superseded (a newer Focus change): not a failure to report.
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
