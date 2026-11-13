import Foundation

final class TuyaLightProvider: LightProvider {
    private let client: TuyaClient
    private let uid: String
    private let lamps = LampCache()
    /// Device specifications (the supported functions) hardly ever change, but fetching one costs
    /// an API call per device. They are cached for the provider's lifetime; `AppState` keeps the
    /// provider across polls and drops it when the credentials change.
    private let capabilityLock = NSLock()
    private var capabilityCache: [String: LightCapabilities] = [:]

    let kind: LightProviderKind = .tuya
    let displayName = LightProviderKind.tuya.title

    init(client: TuyaClient, uid: String) {
        self.client = client
        self.uid = uid
    }

    func syncLights() async throws -> [LampDevice] {
        guard !uid.isEmpty else {
            throw LampControlError.configuration(NSLocalizedString("error.tuya.uid.missing", comment: ""))
        }

        let devices: [TuyaDeviceDTO] = try await client.get("/v1.0/users/\(urlPath(uid))/devices")
        var mapped: [LampDevice] = []
        var firstError: Error?
        for device in devices.uniqued(by: \.id) {
            do {
                if let lamp = try await lamp(from: device) { mapped.append(lamp) }
            } catch {
                // One device whose specification cannot be fetched must not abort the whole sync.
                firstError = firstError ?? error
            }
        }
        // Nothing usable and something failed: that is an outage (credentials, network), not an
        // account without lamps, so let the caller see the error.
        if mapped.isEmpty, let firstError { throw firstError }
        lamps.replace(with: mapped)
        return mapped
    }

    func setPower(deviceId: String, value: Bool) async throws -> LampDevice {
        let lamp = try requireLamp(deviceId)
        guard let switchCode = lamp.capabilities.switchCode else {
            throw LampControlError.tuya(NSLocalizedString("error.tuya.no.power", comment: ""))
        }

        try await sendCommand(deviceId: deviceId, code: switchCode, value: .bool(value))
        return try update(deviceId: deviceId) { $0.power = value }
    }

    func setBrightness(deviceId: String, value: Int) async throws -> LampDevice {
        let lamp = try requireLamp(deviceId)
        guard let brightness = lamp.capabilities.brightness else {
            if lamp.capabilities.colorCode != nil {
                return try await setColorBrightness(deviceId: deviceId, value: value)
            }
            throw LampControlError.tuya(NSLocalizedString("error.tuya.no.brightness", comment: ""))
        }

        let safeValue = min(brightness.max, max(brightness.min, value))
        var commands: [TuyaCommand] = []
        if let switchCode = lamp.capabilities.switchCode {
            commands.append(TuyaCommand(code: switchCode, value: .bool(true)))
        }
        if lamp.capabilities.colorCode != nil, let workModeCode = lamp.capabilities.workModeCode {
            commands.append(TuyaCommand(code: workModeCode, value: .string("white")))
        }
        commands.append(TuyaCommand(code: brightness.code, value: .int(safeValue)))

        try await sendCommands(deviceId: deviceId, commands: commands)
        return try update(deviceId: deviceId) {
            $0.power = true
            $0.brightness = safeValue
            if lamp.capabilities.colorCode != nil {
                $0.workMode = "white"
            }
        }
    }

    func setColorBrightness(deviceId: String, value: Int) async throws -> LampDevice {
        let lamp = try requireLamp(deviceId)
        guard lamp.capabilities.colorCode != nil else {
            return try await setBrightness(deviceId: deviceId, value: value)
        }

        let currentColor = (lamp.color ?? .warm).withValue(value)
        return try await setColor(deviceId: deviceId, color: currentColor)
    }

    func setTemperature(deviceId: String, value: Int) async throws -> LampDevice {
        let lamp = try requireLamp(deviceId)
        guard let temperature = lamp.capabilities.temperature else {
            throw LampControlError.tuya(NSLocalizedString("error.tuya.no.colortemp", comment: ""))
        }

        let safeValue = min(temperature.max, max(temperature.min, value))
        var commands: [TuyaCommand] = []
        if let switchCode = lamp.capabilities.switchCode {
            commands.append(TuyaCommand(code: switchCode, value: .bool(true)))
        }
        let workModeCode = lamp.capabilities.colorCode == nil ? nil : lamp.capabilities.workModeCode
        if let workModeCode {
            commands.append(TuyaCommand(code: workModeCode, value: .string("white")))
        }
        commands.append(TuyaCommand(code: temperature.code, value: .int(safeValue)))

        try await sendCommandsWithModeFallback(deviceId: deviceId, commands: commands, workModeCode: workModeCode)
        return try update(deviceId: deviceId) {
            $0.power = true
            $0.temperature = safeValue
            $0.workMode = "white"
        }
    }

    func setColor(deviceId: String, color: HSVColor) async throws -> LampDevice {
        let lamp = try requireLamp(deviceId)
        guard let colorCode = lamp.capabilities.colorCode else {
            throw LampControlError.tuya(NSLocalizedString("error.tuya.no.color", comment: ""))
        }

        var commands: [TuyaCommand] = []
        if let switchCode = lamp.capabilities.switchCode {
            commands.append(TuyaCommand(code: switchCode, value: .bool(true)))
        }
        let workModeCode = lamp.capabilities.workModeCode
        if let workModeCode {
            commands.append(TuyaCommand(code: workModeCode, value: .string("colour")))
        }
        commands.append(TuyaCommand(code: colorCode, value: .color(color.scaled(for: colorCode, valueScale: lamp.capabilities.colorValueScale))))

        try await sendCommandsWithModeFallback(deviceId: deviceId, commands: commands, workModeCode: workModeCode)
        return try update(deviceId: deviceId) {
            $0.power = true
            $0.color = color
            if $0.capabilities.brightness == nil {
                $0.brightness = color.v
            }
            $0.workMode = "colour"
        }
    }

    private func lamp(from device: TuyaDeviceDTO) async throws -> LampDevice? {
        let capabilities = try await capabilities(for: device.id)

        guard capabilities.switchCode != nil || capabilities.brightness != nil || capabilities.temperature != nil || capabilities.colorCode != nil else {
            return nil
        }

        let status = Dictionary(firstWins: (device.status ?? []).map { ($0.code, $0.value) })
        let switchCode = capabilities.switchCode
        let brightnessCode = capabilities.brightness?.code
        let temperatureCode = capabilities.temperature?.code
        let colorCode = capabilities.colorCode

        return LampDevice(
            id: "\(kind.rawValue):\(device.id)",
            providerID: .tuya,
            nativeID: device.id,
            name: device.name,
            online: device.online,
            power: switchCode.flatMap { status[$0]?.boolValue } ?? false,
            brightness: brightnessCode.flatMap { status[$0]?.intValue } ?? capabilities.brightness?.min,
            temperature: temperatureCode.flatMap { status[$0]?.intValue } ?? capabilities.temperature?.min,
            color: colorCode.flatMap { status[$0]?.hsvValue?.normalized(from: $0, valueScale: capabilities.colorValueScale) },
            workMode: status["work_mode"]?.stringValue,
            capabilities: capabilities
        )
    }

    private func capabilities(for deviceId: String) async throws -> LightCapabilities {
        if let cached = capabilityLock.withLock({ capabilityCache[deviceId] }) { return cached }
        let spec: TuyaSpecResponse = try await client.get("/v1.0/devices/\(urlPath(deviceId))/specifications")
        let parsed = parseCapabilities(spec.functions ?? [])
        capabilityLock.withLock { capabilityCache[deviceId] = parsed }
        return parsed
    }

    private func sendCommand(deviceId: String, code: String, value: TuyaCommandValue) async throws {
        let lamp = try requireLamp(deviceId)
        guard lamp.online else {
            throw LampControlError.offline
        }

        try await postCommands(deviceId: deviceId, commands: [TuyaCommand(code: code, value: value)])
    }

    private func sendCommands(deviceId: String, commands: [TuyaCommand]) async throws {
        let lamp = try requireLamp(deviceId)
        guard lamp.online else {
            throw LampControlError.offline
        }

        try await postCommands(deviceId: deviceId, commands: commands)
    }

    private func sendCommandsWithModeFallback(deviceId: String, commands: [TuyaCommand], workModeCode: String?) async throws {
        do {
            try await sendCommands(deviceId: deviceId, commands: commands)
        } catch {
            // Only "the device does not support this command/value" justifies retrying without
            // work_mode; offline, HTTP, auth and quota errors must reach the user unchanged.
            guard let workModeCode, error.isTuyaUnsupportedCommand else {
                throw error
            }

            let fallbackCommands = commands.filter { $0.code != workModeCode }
            guard fallbackCommands.count != commands.count else {
                throw error
            }

            try await sendCommands(deviceId: deviceId, commands: fallbackCommands)
        }
    }

    private func postCommands(deviceId: String, commands: [TuyaCommand]) async throws {
        do {
            let body = TuyaCommandBody(commands: commands)
            let _: EmptyTuyaResult = try await client.post("/v1.0/devices/\(urlPath(deviceId))/commands", body: body)
        } catch var apiError as TuyaAPIError {
            // Keep the typed error (and its code); only add which commands failed.
            apiError.commandCodes = commands.map(\.code).joined(separator: ", ")
            throw apiError
        }
    }

    private func requireLamp(_ deviceId: String) throws -> LampDevice {
        guard let lamp = lamps[deviceId] else {
            throw LampControlError.tuya(NSLocalizedString("error.tuya.unknown", comment: ""))
        }

        return lamp
    }

    private func update(deviceId: String, mutate: (inout LampDevice) -> Void) throws -> LampDevice {
        guard let lamp = lamps.update(deviceId, mutate) else {
            throw LampControlError.tuya(NSLocalizedString("error.tuya.unknown", comment: ""))
        }
        return lamp
    }

    private func parseCapabilities(_ functions: [TuyaFunctionSpec]) -> LightCapabilities {
        let byCode = Dictionary(firstWins: functions.map { ($0.code, $0) })

        return LightCapabilities(
            switchCode: firstSupportedCode(in: byCode, candidates: ["switch_led", "switch", "switch_1", "switch_light", "switch_lamp"]),
            brightness: parseNumeric(byCode["bright_value_v2"] ?? byCode["bright_value"]),
            temperature: parseNumeric(byCode["temp_value_v2"] ?? byCode["temp_value"]),
            colorCode: byCode["colour_data_v2"] == nil ? (byCode["colour_data"] == nil ? nil : "colour_data") : "colour_data_v2",
            colorValueScale: parseColorValueScale(byCode["colour_data_v2"] ?? byCode["colour_data"]),
            workModeCode: byCode["work_mode"] == nil ? nil : "work_mode"
        )
    }

    private func parseColorValueScale(_ spec: TuyaFunctionSpec?) -> Int? {
        guard let spec, let values = spec.values?.data(using: .utf8) else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: values) as? [String: Any] else {
            return nil
        }

        if let v = json["v"] as? [String: Any], let max = v["max"] as? Int {
            return max <= 255 ? 255 : 1000
        }

        if let range = json["range"] as? [String], range.contains("hsv") {
            return spec.code == "colour_data" ? nil : 1000
        }

        return spec.code == "colour_data_v2" ? 1000 : nil
    }

    private func parseNumeric(_ spec: TuyaFunctionSpec?) -> NumericCapability? {
        guard let spec else { return nil }
        guard ["bright_value", "bright_value_v2", "temp_value", "temp_value_v2"].contains(spec.code) else { return nil }

        if let values = spec.values?.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: values) as? [String: Any] {
            return NumericCapability(
                code: spec.code,
                min: json["min"] as? Int ?? 0,
                max: json["max"] as? Int ?? 1000,
                step: json["step"] as? Int ?? 1
            )
        }

        return NumericCapability(code: spec.code, min: 0, max: 1000, step: 1)
    }

    private func firstSupportedCode(in specs: [String: TuyaFunctionSpec], candidates: [String]) -> String? {
        candidates.first { specs[$0] != nil }
    }

    private func urlPath(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}
