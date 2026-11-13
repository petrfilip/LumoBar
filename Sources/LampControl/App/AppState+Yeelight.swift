import AppKit
import Foundation
import OSLog
import ServiceManagement

extension AppState {
    // MARK: - Yeelight live sync (push notifications)

    func configureYeelightLiveSync() {
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
    func scheduleYeelightRecovery() {
        guard yeelightSettings.isConfigured else { return }
        yeelightRecovery.startIfIdle { [weak self] in await self?.recoverYeelightAddressesIfNeeded() }
    }

    /// Starts/stops/re-points one listener per configured bulb.
    func reconcileYeelightLiveSync() {
        yeelightLiveSync.reconcile(bulbs: yeelightSettings.bulbs)
    }

    /// Maps a pushed (or merged) property set onto the matching lamp with the exact same
    /// function the polling path uses, publishing only when something actually changed.
    func applyYeelightLiveState(bulb: YeelightBulb, properties: [String: String], online: Bool) {
        let next = YeelightLightProvider.makeLamp(bulb: bulb, properties: properties, online: online)
        guard let current = lamps.first(where: { $0.id == next.id }), current != next else { return }
        // A push describing an older state than the user's latest value (echo of an earlier
        // command, a smooth transition's intermediate step) must not move their slider back.
        // The live-sync keeps the latest properties; they are applied when the window closes.
        if online, isHolding(next.id) { return }
        (lightProviders[.yeelight] as? YeelightLightProvider)?.noteExternalState(next)
        updateLamp(next)
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
}
