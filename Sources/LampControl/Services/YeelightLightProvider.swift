import Foundation

final class YeelightLightProvider: LightProvider {
    private let client: YeelightClient
    private let settings: YeelightSettings
    private var lamps: [String: LampDevice] = [:]
    private var bulbsById: [String: YeelightBulb] = [:]

    let kind: LightProviderKind = .yeelight
    let displayName = LightProviderKind.yeelight.title

    private static let propertyKeys = ["power", "bright", "ct", "rgb", "hue", "sat", "color_mode", "name"]

    init(client: YeelightClient = YeelightClient(), settings: YeelightSettings) {
        self.client = client
        self.settings = settings
    }

    func syncLights() async throws -> [LampDevice] {
        guard settings.isConfigured else {
            throw LampControlError.configuration(NSLocalizedString("error.yeelight.none", comment: ""))
        }

        var mapped: [LampDevice] = []
        bulbsById = Dictionary(uniqueKeysWithValues: settings.bulbs.map { ($0.id, $0) })

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
        lamps = Dictionary(uniqueKeysWithValues: mapped.map { ($0.nativeID, $0) })
        return mapped
    }

    func setPower(deviceId: String, value: Bool) async throws -> LampDevice {
        let bulb = try requireBulb(deviceId)
        _ = try await client.sendCommand(host: bulb.host, port: bulb.port, method: "set_power", params: [value ? "on" : "off", "smooth", 200])
        return try update(deviceId: deviceId) { $0.power = value }
    }

    func setBrightness(deviceId: String, value: Int) async throws -> LampDevice {
        let bulb = try requireBulb(deviceId)
        let safeValue = min(100, max(1, value))
        _ = try await client.sendCommand(host: bulb.host, port: bulb.port, method: "set_bright", params: [safeValue, "smooth", 200])
        return try update(deviceId: deviceId) {
            $0.power = true
            $0.brightness = safeValue
        }
    }

    func setTemperature(deviceId: String, value: Int) async throws -> LampDevice {
        let bulb = try requireBulb(deviceId)
        let safeValue = min(6500, max(1700, value))
        _ = try await client.sendCommand(host: bulb.host, port: bulb.port, method: "set_ct_abx", params: [safeValue, "smooth", 200])
        return try update(deviceId: deviceId) {
            $0.power = true
            $0.temperature = safeValue
            $0.color = nil
            $0.workMode = "white"
        }
    }

    func setColor(deviceId: String, color: HSVColor) async throws -> LampDevice {
        let bulb = try requireBulb(deviceId)
        let hue = min(359, max(0, color.h))
        let sat = min(100, max(0, color.s / 10))
        let bri = min(100, max(1, color.v / 10))
        _ = try await client.sendCommand(host: bulb.host, port: bulb.port, method: "set_hsv", params: [hue, sat, "smooth", 200])
        _ = try await client.sendCommand(host: bulb.host, port: bulb.port, method: "set_bright", params: [bri, "smooth", 200])
        return try update(deviceId: deviceId) {
            $0.power = true
            $0.brightness = bri
            $0.color = color
            $0.workMode = "colour"
        }
    }

    private func lamp(from bulb: YeelightBulb, properties: [String], online: Bool) -> LampDevice {
        let dict: [String: String] = Dictionary(uniqueKeysWithValues: zip(Self.propertyKeys, properties + Array(repeating: "", count: max(0, Self.propertyKeys.count - properties.count))))
        let power = dict["power"] == "on"
        let brightness = Int(dict["bright"] ?? "")
        let temperature = Int(dict["ct"] ?? "")
        let bulbName = (dict["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = !bulbName.isEmpty ? bulbName : (bulb.name.isEmpty ? bulb.host : bulb.name)

        // color_mode: 1 = RGB, 2 = color temperature (white), 3 = HSV.
        let workMode: String?
        switch dict["color_mode"] {
        case "1", "3": workMode = "colour"
        case "2": workMode = "white"
        default: workMode = nil
        }

        // The bulb keeps reporting its last hue/sat even in white mode; only
        // expose a color when it is actually shown, so white stays white in the UI.
        var color: HSVColor?
        if workMode != "white", let hue = Int(dict["hue"] ?? ""), let sat = Int(dict["sat"] ?? "") {
            color = HSVColor(
                h: min(360, max(0, hue)),
                s: min(1000, max(0, sat * 10)),
                v: min(1000, max(10, (brightness ?? 100) * 10))
            )
        }

        return LampDevice(
            id: "\(kind.rawValue):\(bulb.id)",
            providerID: kind,
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

    private func requireBulb(_ deviceId: String) throws -> YeelightBulb {
        guard let bulb = bulbsById[deviceId] else {
            throw LampControlError.tuya(NSLocalizedString("error.yeelight.unknown", comment: ""))
        }
        return bulb
    }

    private func requireLamp(_ deviceId: String) throws -> LampDevice {
        guard let lamp = lamps[deviceId] else {
            throw LampControlError.tuya(NSLocalizedString("error.yeelight.unknown", comment: ""))
        }
        return lamp
    }

    private func update(deviceId: String, mutate: (inout LampDevice) -> Void) throws -> LampDevice {
        var lamp = try requireLamp(deviceId)
        mutate(&lamp)
        lamps[deviceId] = lamp
        return lamp
    }
}
