import Foundation

final class HueLightProvider: LightProvider {
    private let client: HueClient
    private let settings: HueSettings
    private var lamps: [String: LampDevice] = [:]

    let kind: LightProviderKind = .philipsHue
    let displayName = LightProviderKind.philipsHue.title

    init(client: HueClient = HueClient(), settings: HueSettings) {
        self.client = client
        self.settings = settings
    }

    func syncLights() async throws -> [LampDevice] {
        guard settings.isConfigured else {
            throw LampControlError.configuration(NSLocalizedString("error.hue.not.configured", comment: ""))
        }

        let lights = try await client.lights(settings: settings)
        let mapped = lights.map { id, light in
            lamp(from: light, nativeID: id)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        lamps = Dictionary(uniqueKeysWithValues: mapped.map { ($0.nativeID, $0) })
        return mapped
    }

    func setPower(deviceId: String, value: Bool) async throws -> LampDevice {
        try await client.setState(settings: settings, lightID: deviceId, state: HueStateCommand(on: value))
        return try update(deviceId: deviceId) { $0.power = value }
    }

    func setBrightness(deviceId: String, value: Int) async throws -> LampDevice {
        let safeValue = min(254, max(1, value))
        try await client.setState(settings: settings, lightID: deviceId, state: HueStateCommand(on: true, bri: safeValue))
        return try update(deviceId: deviceId) {
            $0.power = true
            $0.brightness = safeValue
        }
    }

    func setTemperature(deviceId: String, value: Int) async throws -> LampDevice {
        let safeValue = min(500, max(153, value))
        try await client.setState(settings: settings, lightID: deviceId, state: HueStateCommand(on: true, ct: safeValue))
        return try update(deviceId: deviceId) {
            $0.power = true
            $0.temperature = safeValue
        }
    }

    func setColor(deviceId: String, color: HSVColor) async throws -> LampDevice {
        let hue = min(65_535, max(0, Int(round(Double(color.h) / 360.0 * 65_535.0))))
        let sat = min(254, max(0, Int(round(Double(color.s) / 1000.0 * 254.0))))
        let bri = min(254, max(1, Int(round(Double(color.v) / 1000.0 * 254.0))))
        try await client.setState(settings: settings, lightID: deviceId, state: HueStateCommand(on: true, bri: bri, hue: hue, sat: sat))
        return try update(deviceId: deviceId) {
            $0.power = true
            $0.brightness = bri
            $0.color = color
            $0.workMode = "colour"
        }
    }

    private func lamp(from light: HueLightDTO, nativeID: String) -> LampDevice {
        LampDevice(
            id: "\(kind.rawValue):\(settings.bridgeID.isEmpty ? settings.bridgeIP : settings.bridgeID):\(nativeID)",
            providerID: kind,
            nativeID: nativeID,
            name: light.name,
            online: light.state.reachable ?? true,
            power: light.state.on,
            brightness: light.state.bri,
            temperature: light.state.ct,
            color: hueColor(from: light.state),
            workMode: nil,
            capabilities: LightCapabilities(
                switchCode: "on",
                brightness: NumericCapability(code: "bri", min: 1, max: 254, step: 1),
                temperature: NumericCapability(code: "ct", min: 153, max: 500, step: 1),
                colorCode: "hue_sat",
                colorValueScale: 1000,
                workModeCode: nil
            )
        )
    }

    private func hueColor(from state: HueLightStateDTO) -> HSVColor? {
        guard let hue = state.hue, let sat = state.sat else { return nil }

        return HSVColor(
            h: min(360, max(0, Int(round(Double(hue) / 65_535.0 * 360.0)))),
            s: min(1000, max(0, Int(round(Double(sat) / 254.0 * 1000.0)))),
            v: min(1000, max(10, Int(round(Double(state.bri ?? 254) / 254.0 * 1000.0))))
        )
    }

    private func requireLamp(_ deviceId: String) throws -> LampDevice {
        guard let lamp = lamps[deviceId] else {
            throw LampControlError.tuya(NSLocalizedString("error.hue.unknown", comment: ""))
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
