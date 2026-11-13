import Foundation

struct NanoleafDevice: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String       // display name (user-editable)
    var host: String       // IP address
    var port: Int = 16021
    var authToken: String
    var serial: String = ""

    var baseURL: String { "http://\(host):\(port)/api/v1" }

    enum CodingKeys: String, CodingKey {
        case id, name, host, port, authToken, serial
    }
}

extension NanoleafDevice {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        host = try c.decode(String.self, forKey: .host)
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 16021
        authToken = try c.decode(String.self, forKey: .authToken)
        serial = try c.decodeIfPresent(String.self, forKey: .serial) ?? ""
    }
}

struct NanoleafSettings: Codable {
    var devices: [NanoleafDevice] = []

    var isConfigured: Bool { !devices.isEmpty }

    enum CodingKeys: String, CodingKey { case devices }
}

extension NanoleafSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        devices = try c.decodeLossyArray(NanoleafDevice.self, forKey: .devices)
    }
}

// API response types
struct NanoleafStateResponse: Decodable {
    let name: String?
    let serialNo: String?
    let state: NanoleafState?
    let effects: NanoleafEffects?
}

struct NanoleafState: Decodable {
    let on: NanoleafBoolValue?
    let brightness: NanoleafIntRange?
    let ct: NanoleafIntRange?
    let hue: NanoleafIntRange?
    let sat: NanoleafIntRange?
    let colorMode: String?
}

struct NanoleafEffects: Decodable {
    let selectedEffect: String?
}

struct NanoleafBoolValue: Decodable {
    let value: Bool
}

struct NanoleafIntRange: Decodable {
    let value: Int
    let max: Int?
    let min: Int?
}

struct NanoleafAuthResponse: Decodable {
    let auth_token: String
}

// Command body types
struct NanoleafPowerBody: Encodable {
    let on: NanoleafBoolCmd
    struct NanoleafBoolCmd: Encodable { let value: Bool }
    init(_ value: Bool) { on = .init(value: value) }
}

struct NanoleafBrightnessBody: Encodable {
    struct Brightness: Encodable { let value: Int; let duration: Int = 0 }
    let brightness: Brightness
    init(_ value: Int) { brightness = .init(value: value) }
}

struct NanoleafCTBody: Encodable {
    struct CT: Encodable { let value: Int; let duration: Int = 0 }
    let ct: CT
    init(_ value: Int) { ct = .init(value: value) }
}

struct NanoleafHSBody: Encodable {
    struct HS: Encodable { let value: Int; let duration: Int = 0 }
    let hue: HS
    let sat: HS
    init(hue: Int, sat: Int) { self.hue = .init(value: hue); self.sat = .init(value: sat) }
}
