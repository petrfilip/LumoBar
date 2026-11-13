import Foundation

enum LightProviderKind: String, Codable, CaseIterable, Hashable {
    case tuya
    case philipsHue
    case lifx
    case yeelight
    case govee
    case nanoleaf
    case wiz

    var title: String {
        switch self {
        case .tuya:      "Tuya / Smart Life"
        case .philipsHue: "Philips Hue"
        case .lifx:      "LIFX"
        case .yeelight:  "Yeelight"
        case .govee:     "Govee"
        case .nanoleaf:  "Nanoleaf"
        case .wiz:       "WiZ (Signify)"
        }
    }
}

protocol LightProvider: AnyObject {
    var kind: LightProviderKind { get }
    var displayName: String { get }

    func syncLights() async throws -> [LampDevice]
    func setPower(deviceId: String, value: Bool) async throws -> LampDevice
    func setBrightness(deviceId: String, value: Int) async throws -> LampDevice
    func setTemperature(deviceId: String, value: Int) async throws -> LampDevice
    func setColor(deviceId: String, color: HSVColor) async throws -> LampDevice

    /// How fast values may be streamed to the lamp while the user drags a control. `nil`
    /// (the default) means "send only the final value on release" — the right choice for
    /// cloud APIs with strict rate limits.
    var liveUpdatePolicy: LiveUpdatePolicy? { get }

    /// Same as the plain setters, asking the lamp to fade over `transition` seconds when it
    /// supports it. Providers without fades ignore the parameter.
    func setBrightness(deviceId: String, value: Int, transition: TimeInterval) async throws -> LampDevice
    func setTemperature(deviceId: String, value: Int, transition: TimeInterval) async throws -> LampDevice
    func setColor(deviceId: String, color: HSVColor, transition: TimeInterval) async throws -> LampDevice
}

extension LightProvider {
    var liveUpdatePolicy: LiveUpdatePolicy? { nil }

    func setBrightness(deviceId: String, value: Int, transition: TimeInterval) async throws -> LampDevice {
        try await setBrightness(deviceId: deviceId, value: value)
    }

    func setTemperature(deviceId: String, value: Int, transition: TimeInterval) async throws -> LampDevice {
        try await setTemperature(deviceId: deviceId, value: value)
    }

    func setColor(deviceId: String, color: HSVColor, transition: TimeInterval) async throws -> LampDevice {
        try await setColor(deviceId: deviceId, color: color)
    }
}
