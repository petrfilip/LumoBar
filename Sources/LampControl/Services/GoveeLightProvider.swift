import Foundation

final class GoveeLightProvider: LightProvider {
    private let client: GoveeClient
    private let settings: GoveeSettings
    private let lamps = LampCache()
    private let modelsLock = NSLock()
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
        for device in devices.uniqued(by: \.device) where device.controllable {
            let state = (try? await client.deviceState(apiKey: settings.apiKey, device: device.device, model: device.model)) ?? []
            mapped.append(lamp(from: device, state: state))
        }

        mapped.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        lamps.replace(with: mapped)
        let modelTable = Dictionary(firstWins: devices.map { ($0.device, $0.model) })
        modelsLock.withLock { models = modelTable }
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
        let rgb = color.rgb
        try await sendCommand(deviceId: deviceId, name: "color", value: .color(r: rgb.r, g: rgb.g, b: rgb.b))
        return try update(deviceId: deviceId) {
            $0.power = true
            $0.color = color
            $0.brightness = max(1, min(100, color.v / 10))
            $0.workMode = "colour"
        }
    }

    private func sendCommand(deviceId: String, name: String, value: GoveeCommandValue) async throws {
        guard let model = modelsLock.withLock({ models[deviceId] }) else {
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
            color: hasColor ? color.map { HSVColor.fromRGB(r: $0.r, g: $0.g, b: $0.b, value: Int((Double(min(100, max(1, brightness ?? 100))) * 10).rounded())) } : nil,
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

    private func requireLamp(_ deviceId: String) throws -> LampDevice {
        guard let lamp = lamps[deviceId] else {
            throw LampControlError.device(NSLocalizedString("error.govee.unknown", comment: ""))
        }
        return lamp
    }

    private func update(deviceId: String, mutate: (inout LampDevice) -> Void) throws -> LampDevice {
        guard let lamp = lamps.update(deviceId, mutate) else {
            throw LampControlError.device(NSLocalizedString("error.govee.unknown", comment: ""))
        }
        return lamp
    }
}
