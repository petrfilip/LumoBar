import Foundation

final class WizLightProvider: LightProvider {
    private let client: WizClient
    private let settings: WizSettings
    private var lamps: [String: LampDevice] = [:]

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
        for device in settings.devices {
            if let result = try? await client.getState(device: device) {
                mapped.append(makeLamp(from: device, state: result, online: true))
            } else {
                mapped.append(makeLamp(from: device, state: nil, online: false))
            }
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
        let (r, g, b) = Self.hsvToRGB(color)
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
        guard var lamp = lamps[deviceId] else {
            throw LampControlError.configuration(NSLocalizedString("error.wiz.unknown", comment: ""))
        }
        mutate(&lamp)
        lamps[deviceId] = lamp
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
        let color: HSVColor? = hasColor ? Self.rgbToHSV(r: r, g: g, b: b) : nil

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

    private static func hsvToRGB(_ hsv: HSVColor) -> (r: Int, g: Int, b: Int) {
        let h = Double(hsv.h) / 360.0
        let s = Double(hsv.s) / 1000.0
        let v = Double(hsv.v) / 1000.0
        let i = Int(h * 6)
        let f = h * 6 - Double(i)
        let p = v * (1 - s); let q = v * (1 - f * s); let t = v * (1 - (1 - f) * s)
        var r = 0.0, g = 0.0, b = 0.0
        switch i % 6 {
        case 0: r=v; g=t; b=p
        case 1: r=q; g=v; b=p
        case 2: r=p; g=v; b=t
        case 3: r=p; g=q; b=v
        case 4: r=t; g=p; b=v
        default: r=v; g=p; b=q
        }
        return (Int(r * 255), Int(g * 255), Int(b * 255))
    }

    private static func rgbToHSV(r: Int, g: Int, b: Int) -> HSVColor {
        let rf = Double(r) / 255.0; let gf = Double(g) / 255.0; let bf = Double(b) / 255.0
        let maxV = max(rf, gf, bf); let minV = min(rf, gf, bf); let delta = maxV - minV
        let v = Int(maxV * 1000)
        let s = maxV == 0 ? 0 : Int((delta / maxV) * 1000)
        var h = 0.0
        if delta > 0 {
            if maxV == rf      { h = (gf - bf) / delta + (gf < bf ? 6 : 0) }
            else if maxV == gf { h = (bf - rf) / delta + 2 }
            else               { h = (rf - gf) / delta + 4 }
            h /= 6
        }
        return HSVColor(h: Int(h * 360), s: s, v: v)
    }
}
