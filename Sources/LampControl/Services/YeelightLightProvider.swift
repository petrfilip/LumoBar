import Foundation

final class YeelightLightProvider: LightProvider {
    private let client: YeelightClient
    private let settings: YeelightSettings
    // Caches are read/written from async provider calls (global executor) and, for live
    // push updates, from the main actor — guard them with a lock.
    private let cacheLock = NSLock()
    private var lamps: [String: LampDevice] = [:]
    /// When each cached lamp was last changed by one of *our* commands. A poll that started
    /// before that moment describes the bulb before the command and must not overwrite it.
    private var commandedAt: [String: Date] = [:]
    private var bulbsById: [String: YeelightBulb] = [:]

    let kind: LightProviderKind = .yeelight
    let displayName = LightProviderKind.yeelight.title

    static let propertyKeys = ["power", "bright", "ct", "rgb", "hue", "sat", "color_mode", "name"]

    /// The bulb table is derived from `settings` up front so commands work before the first
    /// `syncLights()` (e.g. right after discovery replaced the provider). `initialLamps` carries
    /// the last known state so the first command result keeps brightness/colour/etc.
    init(client: YeelightClient = YeelightClient(), settings: YeelightSettings, initialLamps: [LampDevice] = []) {
        self.client = client
        self.settings = settings
        self.bulbsById = Dictionary(settings.bulbs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for lamp in initialLamps where lamp.providerID == .yeelight && bulbsById[lamp.nativeID] != nil {
            lamps[lamp.nativeID] = lamp
        }
    }

    func syncLights() async throws -> [LampDevice] {
        guard settings.isConfigured else {
            throw LampControlError.configuration(NSLocalizedString("error.yeelight.none", comment: ""))
        }

        let pollStart = Date()
        var mapped: [LampDevice] = []
        let byId = Dictionary(uniqueKeysWithValues: settings.bulbs.map { ($0.id, $0) })
        cacheLock.withLock { bulbsById = byId }

        for bulb in settings.bulbs {
            let lamp: LampDevice
            do {
                let props = try await client.sendCommand(host: bulb.host, port: bulb.port, method: "get_prop", params: Self.propertyKeys)
                lamp = self.lamp(from: bulb, properties: props, online: true)
            } catch {
                lamp = self.lamp(from: bulb, properties: [], online: false)
            }
            mapped.append(lamp)
        }

        mapped.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let byNative = Dictionary(uniqueKeysWithValues: mapped.map { ($0.nativeID, $0) })
        cacheLock.withLock {
            var next = byNative
            for (id, at) in commandedAt where at > pollStart {
                if let current = lamps[id] { next[id] = current }
            }
            lamps = next
        }
        return mapped
    }

    func setPower(deviceId: String, value: Bool) async throws -> LampDevice {
        let bulb = try requireBulb(deviceId)
        _ = try await client.sendCommand(host: bulb.host, port: bulb.port, method: "set_power", params: [value ? "on" : "off", "smooth", 200])
        return try update(deviceId: deviceId) { $0.power = value }
    }

    /// Intermediate commands of a drag are paced to this (see `LiveUpdatePolicy.yeelight`).
    var liveUpdatePolicy: LiveUpdatePolicy? { .yeelight }

    static let defaultTransition: TimeInterval = 0.2

    /// `smooth` duration in ms; the protocol's minimum is 30.
    static func smoothMilliseconds(_ transition: TimeInterval) -> Int {
        min(5000, max(30, Int((transition * 1000).rounded())))
    }

    func setBrightness(deviceId: String, value: Int) async throws -> LampDevice {
        try await setBrightness(deviceId: deviceId, value: value, transition: Self.defaultTransition)
    }

    func setTemperature(deviceId: String, value: Int) async throws -> LampDevice {
        try await setTemperature(deviceId: deviceId, value: value, transition: Self.defaultTransition)
    }

    func setColor(deviceId: String, color: HSVColor) async throws -> LampDevice {
        try await setColor(deviceId: deviceId, color: color, transition: Self.defaultTransition)
    }

    func setBrightness(deviceId: String, value: Int, transition: TimeInterval) async throws -> LampDevice {
        let bulb = try requireBulb(deviceId)
        let safeValue = min(100, max(1, value))
        // Commands are quota-limited: never repeat what the bulb already shows.
        if let cached = cachedLamp(deviceId), cached.power, cached.brightness == safeValue {
            return cached
        }
        _ = try await client.sendCommand(host: bulb.host, port: bulb.port, method: "set_bright",
                                         params: [safeValue, "smooth", Self.smoothMilliseconds(transition)])
        return try update(deviceId: deviceId) {
            $0.power = true
            $0.brightness = safeValue
        }
    }

    func setTemperature(deviceId: String, value: Int, transition: TimeInterval) async throws -> LampDevice {
        let bulb = try requireBulb(deviceId)
        let safeValue = min(6500, max(1700, value))
        if let cached = cachedLamp(deviceId), cached.power, cached.isWhiteMode, cached.temperature == safeValue {
            return cached
        }
        _ = try await client.sendCommand(host: bulb.host, port: bulb.port, method: "set_ct_abx",
                                         params: [safeValue, "smooth", Self.smoothMilliseconds(transition)])
        return try update(deviceId: deviceId) {
            $0.power = true
            $0.temperature = safeValue
            // `color` is kept: the bulb keeps reporting its last hue/sat while in CT mode, so
            // clearing it here made the next push flip the picker between "no color" and a
            // stale one. The UI decides what is shown from `workMode`, not from `color`.
            $0.workMode = "white"
        }
    }

    func setColor(deviceId: String, color: HSVColor, transition: TimeInterval) async throws -> LampDevice {
        let bulb = try requireBulb(deviceId)
        let hue = min(359, max(0, color.h))
        let sat = min(100, max(0, color.s / 10))
        let bri = min(100, max(1, color.v / 10))
        let smooth = Self.smoothMilliseconds(transition)
        let cached = cachedLamp(deviceId)

        let colorUnchanged = cached.map {
            $0.power && $0.workMode == "colour" && $0.color.map { $0.h == hue && $0.s / 10 == sat } == true
        } ?? false
        if !colorUnchanged {
            _ = try await client.sendCommand(host: bulb.host, port: bulb.port, method: "set_hsv", params: [hue, sat, "smooth", smooth])
        }
        // Brightness is shared with white mode: while dragging across the palette it does
        // not change, so it costs nothing after the first command.
        if cached?.brightness != bri {
            _ = try await client.sendCommand(host: bulb.host, port: bulb.port, method: "set_bright", params: [bri, "smooth", smooth])
        }
        return try update(deviceId: deviceId) {
            $0.power = true
            $0.brightness = bri
            $0.color = color
            $0.workMode = "colour"
        }
    }

    private func cachedLamp(_ deviceId: String) -> LampDevice? {
        cacheLock.withLock { lamps[deviceId] }
    }

    private func lamp(from bulb: YeelightBulb, properties: [String], online: Bool) -> LampDevice {
        Self.makeLamp(bulb: bulb, properties: Self.propertyDictionary(fromGetProp: properties), online: online)
    }

    /// Converts a `get_prop` result array (ordered like `propertyKeys`) into a keyed dictionary.
    static func propertyDictionary(fromGetProp values: [String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: zip(propertyKeys, values))
    }

    /// Yeelight `color_mode`: 1 = RGB, 2 = color temperature, 3 = HSV. Both RGB and HSV render a
    /// color (`set_hsv` leaves the bulb in mode 3), so they are "colour"; only mode 2 is "white".
    /// Anything else (property missing from a partial reply) stays unknown.
    static func workMode(forColorMode colorMode: String?) -> String? {
        switch colorMode {
        case "1", "3": return "colour"
        case "2": return "white"
        default: return nil
        }
    }

    /// Single source of truth mapping raw Yeelight properties (from `get_prop` or merged `props`
    /// push notifications) onto a `LampDevice`.
    static func makeLamp(bulb: YeelightBulb, properties dict: [String: String], online: Bool) -> LampDevice {
        let power = dict["power"] == "on"
        let brightness = Int(dict["bright"] ?? "")
        let temperature = Int(dict["ct"] ?? "")
        let bulbName = (dict["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = !bulbName.isEmpty ? bulbName : (bulb.name.isEmpty ? bulb.host : bulb.name)

        // `hue`/`sat` only describe the colour in HSV mode (3). A bulb set through RGB
        // (color_mode 1: Mi Home, HomeKit, other apps) reports the colour in `rgb` and keeps
        // stale hue/sat from its last HSV command.
        let value = min(1000, max(10, (brightness ?? 100) * 10))
        var color: HSVColor?
        if dict["color_mode"] == "1", let rgb = Int(dict["rgb"] ?? "") {
            color = HSVColor.fromYeelightRGB(rgb, value: value)
        } else if let hue = Int(dict["hue"] ?? ""), let sat = Int(dict["sat"] ?? "") {
            color = HSVColor(
                h: min(360, max(0, hue)),
                s: min(1000, max(0, sat * 10)),
                v: value
            )
        }

        let workMode = Self.workMode(forColorMode: dict["color_mode"])

        return LampDevice(
            id: "\(LightProviderKind.yeelight.rawValue):\(bulb.id)",
            providerID: .yeelight,
            nativeID: bulb.id,
            name: displayName,
            online: online,
            power: power,
            brightness: brightness,
            temperature: temperature,
            color: color,
            workMode: workMode,
            capabilities: LightCapabilities(
                switchCode: "set_power",
                brightness: NumericCapability(code: "set_bright", min: 1, max: 100, step: 1),
                temperature: NumericCapability(code: "set_ct_abx", min: 1700, max: 6500, step: 50),
                colorCode: "set_hsv",
                colorValueScale: 1000,
                workModeCode: nil
            )
        )
    }

    /// Keeps the provider's cached lamp in sync with state pushed by the bulb itself, so that
    /// the next command result is mutated from fresh state rather than the last poll.
    func noteExternalState(_ lamp: LampDevice) {
        cacheLock.lock(); defer { cacheLock.unlock() }
        guard lamps[lamp.nativeID] != nil else { return }
        lamps[lamp.nativeID] = lamp
    }

    private func requireBulb(_ deviceId: String) throws -> YeelightBulb {
        cacheLock.lock(); defer { cacheLock.unlock() }
        guard let bulb = bulbsById[deviceId] ?? settings.bulbs.first(where: { $0.id == deviceId }) else {
            throw LampControlError.yeelight(NSLocalizedString("error.yeelight.unknown", comment: ""))
        }
        return bulb
    }

    private func requireLamp(_ deviceId: String) throws -> LampDevice {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let lamp = lamps[deviceId] { return lamp }
        // Not polled yet: start from what the settings know about the bulb.
        guard let bulb = bulbsById[deviceId] ?? settings.bulbs.first(where: { $0.id == deviceId }) else {
            throw LampControlError.yeelight(NSLocalizedString("error.yeelight.unknown", comment: ""))
        }
        return Self.makeLamp(bulb: bulb, properties: [:], online: true)
    }

    private func update(deviceId: String, mutate: (inout LampDevice) -> Void) throws -> LampDevice {
        var lamp = try requireLamp(deviceId)
        mutate(&lamp)
        cacheLock.withLock {
            lamps[deviceId] = lamp
            commandedAt[deviceId] = Date()
        }
        return lamp
    }
}
