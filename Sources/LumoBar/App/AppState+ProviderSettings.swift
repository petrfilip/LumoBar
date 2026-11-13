import AppKit
import Foundation
import OSLog
import ServiceManagement

extension AppState {
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

    func makeLightProvider(for lamp: LampDevice) throws -> any LightProvider {
        try makeLightProvider(for: lamp.providerID)
    }

    func makeLightProvider(for kind: LightProviderKind) throws -> any LightProvider {
        if let provider = lightProviders[kind] {
            return provider
        }

        let provider: any LightProvider
        switch kind {
        case .tuya:
            provider = try makeTuyaProvider()
        case .philipsHue:
            guard hueSettings.isConfigured else {
                throw LampControlError.configuration(L10n.errorHueNotConfigured)
            }
            provider = HueLightProvider(settings: hueSettings)
        case .lifx:
            guard lifxSettings.isConfigured else {
                throw LampControlError.configuration(L10n.errorLifxTokenMissing)
            }
            provider = LifxLightProvider(settings: lifxSettings)
        case .govee:
            guard goveeSettings.isConfigured else {
                throw LampControlError.configuration(L10n.errorGoveeKeyMissing)
            }
            provider = GoveeLightProvider(settings: goveeSettings)
        case .yeelight:
            guard yeelightSettings.isConfigured else {
                throw LampControlError.configuration(L10n.errorYeelightNone)
            }
            // Bulbs with a connected push listener are not polled (`get_prop`) on top of that.
            provider = YeelightLightProvider(
                settings: yeelightSettings,
                initialLamps: yeelightProviderSeed(),
                liveState: { [weak self] bulbID in self?.yeelightLiveSync.liveProperties(for: bulbID) })
        case .nanoleaf:
            guard nanoleafSettings.isConfigured else {
                throw LampControlError.configuration(L10n.errorNanoleafNone)
            }
            provider = NanoleafLightProvider(settings: nanoleafSettings)
        case .wiz:
            guard wizSettings.isConfigured else {
                throw LampControlError.configuration(L10n.errorWizNone)
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

    func loadHueSettings() {
        do {
            hueSettings = try hueSettingsStore.load()
        } catch {
            showError(L10n.settingsUnreadable("Hue"))
        }
    }

    func loadLifxSettings() {
        do {
            lifxSettings = try lifxSettingsStore.load()
        } catch {
            showError(L10n.settingsUnreadable("LIFX"))
        }
    }

    func loadGoveeSettings() {
        do {
            goveeSettings = try goveeSettingsStore.load()
        } catch {
            showError(L10n.settingsUnreadable("Govee"))
        }
    }

    func loadYeelightSettings() {
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

    func loadNanoleafSettings() {
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

    func loadWizSettings() {
        do { wizSettings = try wizSettingsStore.load() } catch {
            showError(L10n.settingsUnreadable("WiZ"))
        }
    }
}
