import Foundation

struct WizDevice: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var host: String
    var port: Int = 38899

    enum CodingKeys: String, CodingKey { case id, name, host, port }
}

extension WizDevice {
    /// Explicit so fields added later fall back to their defaults for old files.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        host = try c.decode(String.self, forKey: .host)
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 38899
    }
}

struct WizSettings: Codable {
    var devices: [WizDevice] = []
    var isConfigured: Bool { !devices.isEmpty }

    enum CodingKeys: String, CodingKey { case devices }
}

extension WizSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        devices = try c.decodeLossyArray(WizDevice.self, forKey: .devices)
    }
}

struct WizRequest: Encodable {
    let method: String
    let params: WizParams
}

struct WizParams: Encodable {
    var state: Bool?
    var dimming: Int?
    var temp: Int?
    var r: Int?
    var g: Int?
    var b: Int?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let v = state   { try c.encode(v, forKey: .state) }
        if let v = dimming { try c.encode(v, forKey: .dimming) }
        if let v = temp    { try c.encode(v, forKey: .temp) }
        if let v = r       { try c.encode(v, forKey: .r) }
        if let v = g       { try c.encode(v, forKey: .g) }
        if let v = b       { try c.encode(v, forKey: .b) }
    }

    enum CodingKeys: String, CodingKey {
        case state, dimming, temp, r, g, b
    }
}

struct WizStateResult: Decodable {
    let state: Bool?
    let dimming: Int?
    let temp: Int?
    let r: Int?
    let g: Int?
    let b: Int?
    let mac: String?
    let rssi: Int?
    /// Present in the reply to `setPilot` (`{"result":{"success":true}}`).
    let success: Bool?
}

struct WizResponse: Decodable {
    let method: String?
    let result: WizStateResult?
    let error: WizErrorReply?
}

/// `{"method":"setPilot","error":{"code":-32602,"message":"Invalid params"}}`
struct WizErrorReply: Decodable {
    let code: Int?
    let message: String?
}
