import Foundation

/// Owns one `YeelightNotificationListener` per configured bulb and turns their events into
/// state callbacks on the main actor.
///
/// It keeps the latest known raw property set per bulb so that partial `props` deltas can
/// be merged and then mapped with the very same function the polling path uses
/// (`YeelightLightProvider.makeLamp`).
@MainActor
final class YeelightLiveSync {
    /// Called when a bulb's effective state changed: (bulb, merged raw properties, online).
    /// For `online == false` the properties are empty, like a failed poll.
    var onUpdate: ((YeelightBulb, [String: String], Bool) -> Void)?

    private struct Entry {
        var bulb: YeelightBulb
        let listener: YeelightNotificationListener
        /// `nil` until the first snapshot of the current session arrives.
        var properties: [String: String]?
        var online: Bool?
    }

    private var entries: [String: Entry] = [:]

    /// Latest live properties for bulbs whose listener is currently connected and online.
    func liveProperties(for bulbID: String) -> [String: String]? {
        guard let entry = entries[bulbID], entry.online == true else { return nil }
        return entry.properties
    }

    /// Starts listeners for new bulbs, stops those removed, and re-points those whose
    /// address changed. Idempotent.
    func reconcile(bulbs: [YeelightBulb]) {
        let wanted = Dictionary(bulbs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for id in entries.keys where wanted[id] == nil {
            entries[id]?.listener.stop()
            entries[id] = nil
        }

        for bulb in bulbs {
            if var entry = entries[bulb.id] {
                let endpointChanged = entry.bulb.host != bulb.host || entry.bulb.port != bulb.port
                entry.bulb = bulb
                entries[bulb.id] = entry
                if endpointChanged {
                    entry.listener.updateEndpoint(host: bulb.host, port: bulb.port)
                }
                continue
            }

            let listener = YeelightNotificationListener(bulbID: bulb.id, host: bulb.host, port: bulb.port) { [weak self] event in
                // Hop to the main queue in order (a serial -> main async chain preserves order).
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.handle(event, bulbID: bulb.id)
                    }
                }
            }
            entries[bulb.id] = Entry(bulb: bulb, listener: listener, properties: nil, online: nil)
            listener.start()
        }
    }

    func stopAll() {
        for entry in entries.values { entry.listener.stop() }
        entries.removeAll()
    }

    /// Reconnects every listener now (system wake, network change).
    func reconnectAll() {
        for entry in entries.values { entry.listener.reconnectNow() }
    }

    // MARK: - Event handling

    private func handle(_ event: YeelightNotificationListener.Event, bulbID: String) {
        // Events of a bulb that was removed in the meantime are dropped here.
        guard var entry = entries[bulbID] else { return }

        switch event {
        case .snapshot(let properties):
            entry.properties = properties
            entry.online = true
            entries[bulbID] = entry
            onUpdate?(entry.bulb, properties, true)

        case .delta(let delta):
            // Ignore deltas until we have a baseline; the snapshot that follows supersedes them.
            guard var current = entry.properties, entry.online == true else { return }
            var changed = false
            for (key, value) in delta where current[key] != value {
                current[key] = value
                changed = true
            }
            guard changed else { return }
            entry.properties = current
            entries[bulbID] = entry
            onUpdate?(entry.bulb, current, true)

        case .unreachable:
            // Report the offline transition once, not on every failed retry.
            guard entry.online != false else { return }
            entry.online = false
            entry.properties = nil
            entries[bulbID] = entry
            onUpdate?(entry.bulb, [:], false)

        case .disconnected:
            // A reconnect is already scheduled; stay silent unless the reconnect fails.
            break
        }
    }
}
