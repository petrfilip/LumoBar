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
    /// Banner text. Informational messages auto-hide after a few seconds, errors (set via
    /// `showError`) after a longer one, and sticky errors (data recovery) stay until the user
    /// dismisses them (see `BannerPolicy`).
    @Published var message = "" {
        didSet {
            messageIsError = false
            messageIsSticky = false
            scheduleMessageDismiss()
        }
    }
    @Published private(set) var messageIsError = false
    @Published private(set) var messageIsSticky = false
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
    @Published private(set) var collapsedRoomIds: Set<String> = Set(UserDefaults.standard.stringArray(forKey: AppState.collapsedRoomsKey) ?? [])
    @Published var focusMappings: [FocusMapping] = []
    @Published var currentFocusIdentifier: String?
    @Published var availableFocusModes: [FocusMode] = [
        FocusMode(identifier: "do-not-disturb", displayName: L10n.focusModeDoNotDisturb),
        FocusMode(identifier: "focus", displayName: L10n.focusModeFocus),
        FocusMode(identifier: "sleep", displayName: L10n.focusModeSleep)
    ]

    /// Not `@Published`: it is an `ObservableObject` itself, and a nested one does not forward its
    /// changes. Views that show its state observe it directly (see `UpdateServiceObserver`).
    let updateService = UpdateService()

    let settingsStore = SettingsStore()
    let roomStore = RoomStore()
    let focusMappingStore = FocusMappingStore()
    let hueSettingsStore = HueSettingsStore()
    let lifxSettingsStore = LifxSettingsStore()
    let goveeSettingsStore = GoveeSettingsStore()
    let yeelightSettingsStore = YeelightSettingsStore()
    let nanoleafSettingsStore = NanoleafSettingsStore()
    let wizSettingsStore = WizSettingsStore()
    let automationStore = AutomationStore()
    let circadianSettingsStore = CircadianSettingsStore()
    let automationScheduler = AutomationScheduler()
    let circadianService = CircadianService()
    let hueClient = HueClient()
    let sceneStore = LightSceneStore()
    var lightProviders: [LightProviderKind: any LightProvider] = [:]
    var autoSyncTask: Task<Void, Never>?
    /// Pauses the background poll while the Mac sleeps or the session is locked (see `AppState+PowerState.swift`).
    var pollingGate = PollingGate()
    let pollResumeTask = TaskSlot()
    var powerObservers: [PowerObserver] = []
    var syncFailureTracker = SyncFailureTracker()
    let yeelightLiveSync = YeelightLiveSync()
    /// Coalesces and paces what sliders / the color picker stream while the user drags.
    lazy var commandQueue: LampCommandQueue = makeCommandQueue()
    /// Lamps that were off when the user started adjusting their color: the first command
    /// must switch them on (many bulbs reject color commands while off).
    var lampsNeedingPowerOn = Set<String>()
    /// Last known real state of lamps being adjusted, for undoing a preview whose command failed.
    var restorePoints = LampRestorePoints()
    /// Keeps the user's value on screen while they adjust a lamp (see `LampInteractionGuard`).
    var interactionGuard = LampInteractionGuard()
    var holdExpiryTasks: [String: Task<Void, Never>] = [:]
    var lastYeelightDiscovery: Date?
    var isRecoveringYeelight = false
    let yeelightRecovery = TaskSlot()
    // Concurrency state (see StateConsistency.swift).
    var busy = BusyCounter()
    /// Bumped by every user operation and settings save; a background poll that started before
    /// the bump is stale when it finishes and is dropped.
    var syncGeneration = SyncGeneration()
    let focusSceneTask = TaskSlot()
    let circadianApplyTask = TaskSlot()
    let automationTasks = KeyedTasks<UUID>()
    /// True once a sync answered: before that `lamps` is empty and there is nothing to adjust.
    var hasSyncedOnce = false
    /// Adaptive lighting wanted to apply before the first sync; it is applied right after it.
    var circadianApplyPending = false
    /// Minimum delay between automatic (background) network searches.
    let yeelightDiscoveryInterval: TimeInterval = 5 * 60
    let onboardingDismissedKey = "LampControl.onboarding.dismissed"
    static let collapsedRoomsKey = "LampControl.rooms.collapsed"
    let roomsMigratedKey = "LampControl.rooms.migrated"
    /// True while "Reset all settings" runs: blocks background persistence so
    /// nothing re-creates the files that were just removed.
    var isResettingApp = false

    init() {
        configureYeelightLiveSync()
        configurePollingGate()
        loadScenes()
        lampOrderIds = settingsStore.loadLampOrder()
        Task { await runStartupSequence() }
    }

    // MARK: Launch at login

    /// Mirrors `SMAppService.mainApp.status`; refreshed on demand (Settings appear / after a change).
    @Published var loginItemStatus: SMAppService.Status = SMAppService.mainApp.status

    // MARK: Focus automation (URL scheme)

    static let resetLog = Logger(subsystem: "fr.hugoinformatique.lampcontrol", category: "Reset")
    static let focusLog = Logger(subsystem: "fr.hugoinformatique.lampcontrol", category: "FocusAutomation")
    var isFocusAutomationReady = false
    var pendingFocusURLs: [URL] = []

    // MARK: Room expansion

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
        UserDefaults.standard.set(Array(collapsedRoomIds).sorted(), forKey: Self.collapsedRoomsKey)
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

    /// Visible height of the display the popover opens on. `NSScreen.main` is
    /// the display with the key window — often the *other* monitor — so a
    /// popover sized for a taller screen did not fit and AppKit shifted it
    /// away from the menu bar icon.
    @Published var popoverScreenVisibleHeight: CGFloat?

    /// Closes the menu-bar popover without quitting. Set by `AppDelegate`.
    var closePopover: (() -> Void)?

    func showError(_ error: Error) {
        showError(error.localizedDescription)
    }

    /// `sticky` keeps the banner until the user dismisses it: for notices that must not be
    /// missed, such as a data file that was set aside.
    func showError(_ text: String, sticky: Bool = false) {
        message = text
        messageIsError = true
        messageIsSticky = sticky
        scheduleMessageDismiss()
    }

    /// The banner's × button.
    func dismissMessage() {
        message = ""
    }

    private func scheduleMessageDismiss() {
        messageDismissTask?.cancel()
        guard !message.isEmpty,
              let lifetime = BannerPolicy.lifetime(isError: messageIsError, isSticky: messageIsSticky) else { return }
        let shown = message
        messageDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(lifetime * 1_000_000_000))
            guard let self, !Task.isCancelled, self.message == shown else { return }
            self.message = ""
        }
    }
}

enum ControlTab {
    case lamps
    case settings
}
