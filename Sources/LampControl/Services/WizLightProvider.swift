import Foundation

final class WizLightProvider: LightProvider {
    private let client: WizClient
    private let settings: WizSettings
    private let lamps = LampCache()

    let kind: LightProviderKind = .wiz
    let displayName = LightProviderKind.wiz.title

    init(client: WizClient = WizClient(), settings: WizSettings) {
        self.client = client
        self.settings = settings
    }

    func syncLights() async throws -> [LampDevice] {
        guard settings.isConfigured else {
            throw LampControlError.configuration(NSLocalizedString("error.wiz.none", comment: ""))
        }

        var mapped: [LampDevice] = []
        for device in settings.devices.uniqued(by: { nativeID(for: $0) }) {
            if let result = try? await client.getState(device: device) {
                mapped.append(makeLamp(from: device, state: result, online: true))
            } else {
                mapped.append(makeLamp(from: device, state: nil, online: false))
            }
        }

        mapped.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        lamps.replace(with: mapped)
        return mapped
    }

    func setPower(deviceId: String, value: Bool) async throws -> LampDevice {
        let (device, _) = try requireDevice(deviceId)
        try await client.setPower(device: device, value: value)
        return try update(deviceId: deviceId) { $0.power = value }
    }

    func setBrightness(deviceId: String, value: Int) async throws -> LampDevice {
        let (device, _) = try requireDevice(deviceId)
        let safe = min(100, max(1, value))
        try await client.setDimming(device: device, value: safe)
        return try update(deviceId: deviceId) {
            $0.power = true
            $0.brightness = safe
        }
    }

    func setTemperature(deviceId: String, value: Int) async throws -> LampDevice {
        let (device, lamp) = try requireDevice(deviceId)
        let cap = lamp.capabilities.temperature
        let safe = min(cap?.max ?? 6500, max(cap?.min ?? 2200, value))
        try await client.setTemp(device: device, kelvin: safe)
        return try update(deviceId: deviceId) {
            $0.power = true
            $0.temperature = safe
        }
    }

    func setColor(deviceId: String, color: HSVColor) async throws -> LampDevice {
        let (device, _) = try requireDevice(deviceId)
        let (r, g, b) = color.rgb
        let dimming = max(1, min(100, color.v / 10))
        try await client.setRGB(device: device, r: r, g: g, b: b, dimming: dimming)
        return try update(deviceId: deviceId) {
            $0.power = true
            $0.color = color
        }
    }

    // MARK: - Private

    private func requireDevice(_ deviceId: String) throws -> (WizDevice, LampDevice) {
        guard let lamp = lamps[deviceId] else {
            throw LampControlError.configuration(NSLocalizedString("error.wiz.unknown.sync", comment: ""))
        }
        guard let device = settings.devices.first(where: { nativeID(for: $0) == deviceId }) else {
            throw LampControlError.configuration(NSLocalizedString("error.wiz.not.in.settings", comment: ""))
        }
        guard lamp.online else { throw LampControlError.offline }
        return (device, lamp)
    }

    private func update(deviceId: String, mutate: (inout LampDevice) -> Void) throws -> LampDevice {
        guard let lamp = lamps.update(deviceId, mutate) else {
            throw LampControlError.configuration(NSLocalizedString("error.wiz.unknown", comment: ""))
        }
        return lamp
    }

    private func nativeID(for device: WizDevice) -> String { device.host }

    private func makeLamp(from device: WizDevice, state: WizStateResult?, online: Bool) -> LampDevice {
        let nid = nativeID(for: device)
        let power = state?.state ?? false
        let brightness = state?.dimming
        let temperature = state?.temp
        let r = state?.r ?? 0; let g = state?.g ?? 0; let b = state?.b ?? 0
        let hasColor = (r + g + b) > 0
        let color: HSVColor? = hasColor ? HSVColor.fromRGB(r: r, g: g, b: b) : nil

        let capabilities = LightCapabilities(
            switchCode: "state",
            brightness: NumericCapability(code: "dimming", min: 1, max: 100, step: 1),
            temperature: NumericCapability(code: "temp", min: 2200, max: 6500, step: 100),
            colorCode: "rgb",
            colorValueScale: nil,
            workModeCode: nil
        )

        return LampDevice(
            id: "wiz:\(nid)",
            providerID: .wiz,
            nativeID: nid,
            name: device.name.isEmpty ? device.host : device.name,
            online: online,
            power: power,
            brightness: brightness,
            temperature: temperature,
            color: color,
            workMode: nil,
            capabilities: capabilities
        )
    }
}
