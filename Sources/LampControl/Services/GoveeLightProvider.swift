import Foundation

final class GoveeLightProvider: LightProvider {
    private let client: GoveeClient
    private let settings: GoveeSettings
    private var lamps: [String: LampDevice] = [:]
    private var models: [String: String] = [:]

    let kind: LightProviderKind = .govee
    let displayName = LightProviderKind.govee.title

    init(client: GoveeClient = GoveeClient(), settings: GoveeSettings) {
        self.client = client
        self.settings = settings
    }

    func syncLights() async throws -> [LampDevice] {
        guard settings.isConfigured else {
            throw LampControlError.configuration(NSLocalizedString("error.govee.apikey.missing", comment: ""))
        }

        let devices = try await client.listDevices(apiKey: settings.apiKey)
        var mapped: [LampDevice] = []
        for device in devices where device.controllable {
            let state = (try? await client.deviceState(apiKey: settings.apiKey, device: device.device, model: device.model)) ?? []
            mapped.append(lamp(from: device, state: state))
        }

        mapped.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        lamps = Dictionary(uniqueKeysWithValues: mapped.map { ($0.nativeID, $0) })
        models = Dictionary(uniqueKeysWithValues: devices.map { ($0.device, $0.model) })
        return mapped
    }

    func setPower(deviceId: String, value: Bool) async throws -> LampDevice {
        try await sendCommand(deviceId: deviceId, name: "turn", value: .string(value ? "on" : "off"))
        return try update(deviceId: deviceId) { $0.power = value }
    }

    func setBrightness(deviceId: String, value: Int) async throws -> LampDevice {
        let safeValue = min(100, max(1, value))
        try await sendCommand(deviceId: deviceId, name: "brightness", value: .int(safeValue))
        return try update(deviceId: deviceId) {
            $0.power = true
            $0.brightness = safeValue
        }
    }

    func setTemperature(deviceId: String, value: Int) async throws -> LampDevice {
        let lamp = try requireLamp(deviceId)
        let bounds = lamp.capabilities.temperature
        let minK = bounds?.min ?? 2000
        let maxK = bounds?.max ?? 9000
        let safeValue = min(maxK, max(minK, value))
        try await sendCommand(deviceId: deviceId, name: "colorTem", value: .int(safeValue))
        return try update(deviceId: deviceId) {
            $0.power = true
            $0.temperature = safeValue
            $0.workMode = "white"
        }
    }

    func setColor(deviceId: String, color: HSVColor) async throws -> LampDevice {
        let rgb = rgb(from: color)
        try await sendCommand(deviceId: deviceId, name: "color", value: .color(r: rgb.r, g: rgb.g, b: rgb.b))
        return try update(deviceId: deviceId) {
            $0.power = true
            $0.color = color
            $0.brightness = max(1, min(100, color.v / 10))
            $0.workMode = "colour"
        }
    }

    private func sendCommand(deviceId: String, name: String, value: GoveeCommandValue) async throws {
        guard let model = models[deviceId] else {
            throw LampControlError.device(NSLocalizedString("error.govee.model.unknown", comment: ""))
        }

        let body = GoveeControlBody(device: deviceId, model: model, cmd: GoveeCommand(name: name, value: value))
        try await client.control(apiKey: settings.apiKey, body: body)
    }

    private func lamp(from device: GoveeDeviceDTO, state: [GoveeStatePropertyDTO]) -> LampDevice {
        let supports = Set(device.supportCmds.map { $0.lowercased() })
        let online = state.first(where: { $0.online != nil })?.online ?? true
        let powerState = state.first(where: { $0.powerState != nil })?.powerState
        let brightness = state.first(where: { $0.brightness != nil })?.brightness
        let colorTem = state.first(where: { $0.colorTem != nil })?.colorTem
        let color = state.first(where: { $0.color != nil })?.color

        let temperatureBounds = device.properties?.colorTem?.range
        let hasColor = supports.contains("color")
        let hasTemperature = supports.contains("colortem") && temperatureBounds != nil

        return LampDevice(
            id: "\(kind.rawValue):\(device.device)",
            providerID: kind,
            nativeID: device.device,
            name: device.deviceName.isEmpty ? device.model : device.deviceName,
            online: online,
            power: powerState?.lowercased() == "on",
            brightness: brightness,
            temperature: colorTem,
            color: hasColor ? color.map { hsv(fromR: $0.r, g: $0.g, b: $0.b, brightness: brightness ?? 100) } : nil,
            workMode: nil,
            capabilities: LightCapabilities(
                switchCode: "turn",
                brightness: supports.contains("brightness") ? NumericCapability(code: "brightness", min: 1, max: 100, step: 1) : nil,
                temperature: hasTemperature ? NumericCapability(code: "colorTem", min: temperatureBounds!.min, max: temperatureBounds!.max, step: 50) : nil,
                colorCode: hasColor ? "color" : nil,
                colorValueScale: 1000,
                workModeCode: nil
            )
        )
    }

    private func rgb(from color: HSVColor) -> (r: Int, g: Int, b: Int) {
        let h = Double(color.h) / 360.0
        let s = Double(color.s) / 1000.0
        let v = Double(color.v) / 1000.0

        let i = Int(h * 6)
        let f = h * 6 - Double(i)
        let p = v * (1 - s)
        let q = v * (1 - f * s)
        let t = v * (1 - (1 - f) * s)

        let (r, g, b): (Double, Double, Double)
        switch i % 6 {
        case 0: (r, g, b) = (v, t, p)
        case 1: (r, g, b) = (q, v, p)
        case 2: (r, g, b) = (p, v, t)
        case 3: (r, g, b) = (p, q, v)
        case 4: (r, g, b) = (t, p, v)
        default: (r, g, b) = (v, p, q)
        }

        return (
            r: min(255, max(0, Int(round(r * 255)))),
            g: min(255, max(0, Int(round(g * 255)))),
            b: min(255, max(0, Int(round(b * 255))))
        )
    }

    private func hsv(fromR r: Int, g: Int, b: Int, brightness: Int) -> HSVColor {
        let rd = Double(r) / 255.0
        let gd = Double(g) / 255.0
        let bd = Double(b) / 255.0

        let maxC = max(rd, gd, bd)
        let minC = min(rd, gd, bd)
        let delta = maxC - minC

        var hue: Double = 0
        if delta > 0 {
            if maxC == rd {
                hue = 60 * (((gd - bd) / delta).truncatingRemainder(dividingBy: 6))
            } else if maxC == gd {
                hue = 60 * (((bd - rd) / delta) + 2)
            } else {
                hue = 60 * (((rd - gd) / delta) + 4)
            }
        }
        if hue < 0 { hue += 360 }

        let saturation = maxC == 0 ? 0 : Int(round((delta / maxC) * 1000))
        let value = Int(round(Double(min(100, max(1, brightness))) * 10))

        return HSVColor(h: Int(round(hue)), s: saturation, v: value)
    }

    private func requireLamp(_ deviceId: String) throws -> LampDevice {
        guard let lamp = lamps[deviceId] else {
            throw LampControlError.device(NSLocalizedString("error.govee.unknown", comment: ""))
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
