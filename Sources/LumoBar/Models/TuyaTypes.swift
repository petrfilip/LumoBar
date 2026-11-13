import Foundation

struct LampDevice: Identifiable, Codable, Equatable {
    let id: String
    var providerID: LightProviderKind
    var nativeID: String
    var name: String
    var online: Bool
    var power: Bool
    var brightness: Int?
    var temperature: Int?
    var color: HSVColor?
    var workMode: String?
    var capabilities: LightCapabilities

    func withPower(_ value: Bool) -> LampDevice {
        var next = self
        next.power = value
        return next
    }

    func withBrightness(_ value: Int) -> LampDevice {
        var next = self
        if next.capabilities.brightness != nil {
            next.brightness = value
        } else if next.capabilities.colorCode != nil {
            next.color = (next.color ?? .warm).withValue(value)
            next.workMode = "colour"
            next.power = true
        }
        return next
    }

    func withTemperature(_ value: Int) -> LampDevice {
        var next = self
        next.temperature = value
        next.power = true
        next.workMode = "white"
        return next
    }

    func withColor(_ value: HSVColor) -> LampDevice {
        var next = self
        next.color = value
        next.power = true
        next.workMode = "colour"
        return next
    }
}

struct LightCapabilities: Codable, Equatable {
    var switchCode: String?
    var brightness: NumericCapability?
    var temperature: NumericCapability?
    var colorCode: String?
    var colorValueScale: Int?
    var workModeCode: String?
}

struct NumericCapability: Codable, Equatable {
    var code: String
    var min: Int
    var max: Int
    var step: Int
}

struct HSVColor: Codable, Equatable, Hashable {
    var h: Int
    var s: Int
    var v: Int

    static let warm = HSVColor(h: 42, s: 420, v: 900)
    static let defaultColorValue = 1000

    func scaled(for code: String, valueScale: Int? = nil) -> HSVColor {
        if code == "colour_data", valueScale == 255 {
            return HSVColor(
                h: min(360, max(0, h)),
                s: min(255, max(0, Int(round(Double(s) / 1000.0 * 255.0)))),
                v: min(255, max(1, Int(round(Double(v) / 1000.0 * 255.0))))
            )
        }

        return clamped(maxSaturation: 1000, maxValue: 1000)
    }

    func normalized(from code: String, valueScale: Int? = nil) -> HSVColor {
        if code == "colour_data", valueScale == 255 {
            return HSVColor(
                h: min(360, max(0, h)),
                s: min(1000, max(0, Int(round(Double(s) / 255.0 * 1000.0)))),
                v: min(1000, max(10, Int(round(Double(v) / 255.0 * 1000.0))))
            )
        }

        return clamped(maxSaturation: 1000, maxValue: 1000)
    }

    private func clamped(maxSaturation: Int, maxValue: Int) -> HSVColor {
        HSVColor(
            h: min(360, max(0, h)),
            s: min(maxSaturation, max(0, s)),
            v: min(maxValue, max(0, v))
        )
    }

    // Saturation is kept as picked: the spectrum picker fades to white at the
    // top, and forcing a minimum saturation made white impossible to select.
    func vivid() -> HSVColor {
        HSVColor(h: h, s: s, v: HSVColor.defaultColorValue)
    }

    func withValue(_ value: Int) -> HSVColor {
        HSVColor(h: h, s: s, v: min(1000, max(10, value)))
    }

    static let white = HSVColor(h: 0, s: 0, v: 1000)

    /// Below ~6 % saturation a color reads as white; lamps with a white
    /// channel render that far better in color-temperature mode.
    var isNearWhite: Bool { s < 60 }
}

struct TuyaEnvelope<Result: Decodable>: Decodable {
    let success: Bool
    let code: TuyaFlexibleString?
    let msg: String?
    let result: Result?
}

struct TuyaFlexibleString: Decodable, CustomStringConvertible {
    let description: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            description = string
        } else if let int = try? container.decode(Int.self) {
            description = String(int)
        } else {
            description = ""
        }
    }
}

struct TuyaTokenResult: Decodable {
    let accessToken: String
    let expireTime: Int
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expireTime = "expire_time"
        case refreshToken = "refresh_token"
    }
}

struct TuyaDeviceDTO: Decodable {
    let id: String
    let name: String
    let online: Bool
    let category: String?
    let status: [TuyaStatusDTO]?
}

struct TuyaStatusDTO: Decodable {
    let code: String
    let value: TuyaValue
}

enum TuyaValue: Decodable, Equatable {
    case bool(Bool)
    case int(Int)
    case string(String)
    case object([String: TuyaValue])
    case array([TuyaValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: TuyaValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([TuyaValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        if case .int(let value) = self { return value }
        if case .string(let value) = self { return Int(value) }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var hsvValue: HSVColor? {
        switch self {
        case .object(let object):
            guard let h = object["h"]?.intValue, let s = object["s"]?.intValue, let v = object["v"]?.intValue else {
                return nil
            }
            return HSVColor(h: h, s: s, v: v)
        case .string(let value):
            guard let data = value.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let h = json["h"] as? Int,
                  let s = json["s"] as? Int,
                  let v = json["v"] as? Int else {
                return nil
            }
            return HSVColor(h: h, s: s, v: v)
        default:
            return nil
        }
    }
}

struct TuyaSpecResponse: Decodable {
    let functions: [TuyaFunctionSpec]?
}

struct TuyaFunctionSpec: Decodable {
    let code: String
    let type: String?
    let values: String?
}

struct TuyaCommandBody: Encodable {
    let commands: [TuyaCommand]
}

struct TuyaCommand: Encodable {
    let code: String
    let value: TuyaCommandValue
}

enum TuyaCommandValue: Encodable {
    case bool(Bool)
    case int(Int)
    case string(String)
    case color(HSVColor)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .color(let value):
            try container.encode(value)
        }
    }
}

struct EmptyTuyaResult: Decodable {
    init() {}
    init(from decoder: Decoder) throws {}
}
