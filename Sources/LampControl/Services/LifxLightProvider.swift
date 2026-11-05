import Foundation

final class LifxLightProvider: LightProvider {
    private let client: LifxClient
    private let settings: LifxSettings
    private var lamps: [String: LampDevice] = [:]

    let kind: LightProviderKind = .lifx
    let displayName = LightProviderKind.lifx.title

    init(client: LifxClient = LifxClient(), settings: LifxSettings) {
        self.client = client
        self.settings = settings
    }

    func syncLights() async throws -> [LampDevice] {
        guard settings.isConfigured else {
            throw LampControlError.configuration(NSLocalizedString("error.lifx.token.missing", comment: ""))
        }

        let lights = try await client.listLights(token: settings.token)
        let mapped = lights.map(lamp(from:))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        lamps = Dictionary(uniqueKeysWithValues: mapped.map { ($0.nativeID, $0) })
        return mapped
    }

    func setPower(deviceId: String, value: Bool) async throws -> LampDevice {
        try await client.setState(token: settings.token, selector: selector(for: deviceId), command: LifxStateCommand(power: value ? "on" : "off", duration: 0.2, fast: true))
        return try update(deviceId: deviceId) { $0.power = value }
    }

    func setBrightness(deviceId: String, value: Int) async throws -> LampDevice {
        let safeValue = min(1000, max(1, value))
        try await client.setState(token: settings.token, selector: selector(for: deviceId), command: LifxStateCommand(power: "on", brightness: Double(safeValue) / 1000.0, duration: 0.2, fast: true))
        return try update(deviceId: deviceId) {
            $0.power = true
            $0.brightness = safeValue
        }
    }

    func setTemperature(deviceId: String, value: Int) async throws -> LampDevice {
        let safeValue = min(9000, max(1500, value))
        try await client.setState(token: settings.token, selector: selector(for: deviceId), command: LifxStateCommand(power: "on", color: "kelvin:\(safeValue)", duration: 0.2, fast: true))
        return try update(deviceId: deviceId) {
            $0.power = true
            $0.temperature = safeValue
            $0.workMode = "white"
        }
    }

    func setColor(deviceId: String, color: HSVColor) async throws -> LampDevice {
        let lifxColor = "hue:\(color.h) saturation:\(Double(color.s) / 1000.0) brightness:\(Double(color.v) / 1000.0)"
        try await client.setState(token: settings.token, selector: selector(for: deviceId), command: LifxStateCommand(power: "on", color: lifxColor, duration: 0.2, fast: true))
        return try update(deviceId: deviceId) {
            $0.power = true
            $0.brightness = color.v
            $0.color = color
            $0.workMode = "colour"
        }
    }

    private func lamp(from light: LifxLightDTO) -> LampDevice {
        let hasColor = light.product?.capabilities?.hasColor ?? true
        let hasTemperature = light.product?.capabilities?.hasVariableColorTemp ?? true
        let brightness = min(1000, max(1, Int(round((light.brightness ?? 1.0) * 1000.0))))
        let color = light.color.map {
            HSVColor(
                h: min(360, max(0, Int(round($0.hue ?? 0)))),
                s: min(1000, max(0, Int(round(($0.saturation ?? 0) * 1000.0)))),
                v: brightness
            )
        }

        return LampDevice(
            id: "\(kind.rawValue):\(light.id)",
            providerID: kind,
            nativeID: light.id,
            name: light.label,
            online: light.connected,
            power: light.power == "on",
            brightness: brightness,
            temperature: light.color?.kelvin,
            color: hasColor ? color : nil,
            workMode: hasColor && (color?.s ?? 0) > 0 ? "colour" : "white",
            capabilities: LightCapabilities(
                switchCode: "power",
                brightness: NumericCapability(code: "brightness", min: 1, max: 1000, step: 1),
                temperature: hasTemperature ? NumericCapability(code: "kelvin", min: 1500, max: 9000, step: 50) : nil,
                colorCode: hasColor ? "hsbk" : nil,
                colorValueScale: 1000,
                workModeCode: nil
            )
        )
    }

    private func selector(for deviceId: String) -> String {
        "id:\(deviceId)"
    }

    private func requireLamp(_ deviceId: String) throws -> LampDevice {
        guard let lamp = lamps[deviceId] else {
            throw LampControlError.tuya(NSLocalizedString("error.lifx.unknown", comment: ""))
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
