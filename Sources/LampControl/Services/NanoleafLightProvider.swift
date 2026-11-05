import Foundation

final class NanoleafLightProvider: LightProvider {
    private let client: NanoleafClient
    private let settings: NanoleafSettings
    private var lamps: [String: LampDevice] = [:]

    let kind: LightProviderKind = .nanoleaf
    let displayName = LightProviderKind.nanoleaf.title

    init(client: NanoleafClient = NanoleafClient(), settings: NanoleafSettings) {
        self.client = client
        self.settings = settings
    }

    func syncLights() async throws -> [LampDevice] {
        guard settings.isConfigured else {
            throw LampControlError.configuration(NSLocalizedString("error.nanoleaf.none", comment: ""))
        }

        var mapped: [LampDevice] = []
        for device in settings.devices {
            let lamp: LampDevice
            if let state = try? await client.fetchState(device: device) {
                lamp = makeLamp(from: device, state: state, online: true)
            } else {
                lamp = makeLamp(from: device, state: nil, online: false)
            }
            mapped.append(lamp)
        }

        mapped.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        lamps = Dictionary(uniqueKeysWithValues: mapped.map { ($0.nativeID, $0) })
        return mapped
    }

    func setPower(deviceId: String, value: Bool) async throws -> LampDevice {
        let (device, _) = try requireDevice(deviceId)
        try await client.setPower(device: device, value: value)
        return try update(deviceId: deviceId) { $0.power = value }
    }

    func setBrightness(deviceId: String, value: Int) async throws -> LampDevice {
        let (device, _) = try requireDevice(deviceId)
        let safe = min(100, max(0, value))
        try await client.setBrightness(device: device, value: safe)
        return try update(deviceId: deviceId) {
            $0.power = true
            $0.brightness = safe
        }
    }

    func setTemperature(deviceId: String, value: Int) async throws -> LampDevice {
        let (device, lamp) = try requireDevice(deviceId)
        let cap = lamp.capabilities.temperature
        let safe = min(cap?.max ?? 6500, max(cap?.min ?? 1200, value))
        try await client.setCT(device: device, value: safe)
        return try update(deviceId: deviceId) {
            $0.power = true
            $0.temperature = safe
            $0.workMode = "ct"
        }
    }

    func setColor(deviceId: String, color: HSVColor) async throws -> LampDevice {
        let (device, _) = try requireDevice(deviceId)
        let hue = min(360, max(0, color.h))
        let sat = min(100, max(0, color.s / 10))
        try await client.setHS(device: device, hue: hue, sat: sat)
        return try update(deviceId: deviceId) {
            $0.power = true
            $0.color = color
            $0.workMode = "hs"
        }
    }

    // MARK: - Private

    private func requireDevice(_ deviceId: String) throws -> (NanoleafDevice, LampDevice) {
        guard let lamp = lamps[deviceId] else {
            throw LampControlError.configuration(NSLocalizedString("error.nanoleaf.unknown.sync", comment: ""))
        }
        guard let device = settings.devices.first(where: { nativeID(for: $0) == deviceId }) else {
            throw LampControlError.configuration(NSLocalizedString("error.nanoleaf.not.in.settings", comment: ""))
        }
        guard lamp.online else { throw LampControlError.offline }
        return (device, lamp)
    }

    private func update(deviceId: String, mutate: (inout LampDevice) -> Void) throws -> LampDevice {
        guard var lamp = lamps[deviceId] else {
            throw LampControlError.configuration(NSLocalizedString("error.nanoleaf.unknown", comment: ""))
        }
        mutate(&lamp)
        lamps[deviceId] = lamp
        return lamp
    }

    private func nativeID(for device: NanoleafDevice) -> String {
        "\(device.host):\(device.port)"
    }

    private func makeLamp(from device: NanoleafDevice, state: NanoleafStateResponse?, online: Bool) -> LampDevice {
        let nid = nativeID(for: device)
        let s = state?.state
        let power = s?.on?.value ?? false
        let brightness = s?.brightness?.value
        let temperature = s?.ct?.value
        let colorMode = s?.colorMode
        let hue = s?.hue?.value ?? 0
        let sat = (s?.sat?.value ?? 0) * 10
        let val = (brightness ?? 100) * 10
        let color: HSVColor? = (colorMode == "hs") ? HSVColor(h: hue, s: sat, v: val) : nil

        let brightnessCap = NumericCapability(code: "brightness", min: 0, max: 100, step: 1)
        let temperatureCap = NumericCapability(code: "ct", min: 1200, max: 6500, step: 100)

        let capabilities = LightCapabilities(
            switchCode: "on",
            brightness: brightnessCap,
            temperature: temperatureCap,
            colorCode: "hs",
            colorValueScale: nil,
            workModeCode: nil
        )

        return LampDevice(
            id: "nanoleaf:\(nid)",
            providerID: .nanoleaf,
            nativeID: nid,
            name: device.name.isEmpty ? (state?.name ?? device.host) : device.name,
            online: online,
            power: power,
            brightness: brightness,
            temperature: temperature,
            color: color,
            workMode: colorMode,
            capabilities: capabilities
        )
    }
}
