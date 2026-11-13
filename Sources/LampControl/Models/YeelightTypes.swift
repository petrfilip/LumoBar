import Foundation

struct YeelightSettings: Codable, Equatable {
    var bulbs: [YeelightBulb] = []

    var isConfigured: Bool {
        !bulbs.isEmpty
    }

    enum CodingKeys: String, CodingKey { case bulbs }
}

extension YeelightSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bulbs = try c.decodeLossyArray(YeelightBulb.self, forKey: .bulbs)
    }
}

struct YeelightBulb: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var host: String
    var port: Int
    var name: String
    /// Yeelight's own device id (e.g. `0x000000000015243f`, lowercased), learned from SSDP
    /// discovery. Stable across IP changes, used to follow the bulb when its address changes.
    /// Optional so settings files written before this field existed still decode.
    var deviceId: String?

    init(id: String = UUID().uuidString, host: String, port: Int = 55443, name: String = "", deviceId: String? = nil) {
        self.id = id
        self.host = host
        self.port = port
        self.name = name.isEmpty ? host : name
        self.deviceId = deviceId?.lowercased()
    }
}

struct YeelightResponse: Decodable {
    let id: Int?
    let result: [String]?
    let error: YeelightErrorPayload?
}

struct YeelightErrorPayload: Decodable {
    let code: Int
    let message: String
}

/// Parsing and validation of a user-entered `host[:port]` Yeelight address.
enum YeelightAddress {
    static let defaultPort = 55443

    static func isValidPort(_ port: Int) -> Bool {
        (1...65535).contains(port)
    }

    /// Splits `host[:port]`. A missing or non-numeric port suffix means the default port.
    /// Throws a configuration error when a numeric port is outside 1...65535.
    static func parse(_ raw: String) throws -> (host: String, port: Int) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // More than one colon is a bare IPv6 literal, not `host:port`.
        let colonCount = trimmed.filter { $0 == ":" }.count
        guard colonCount == 1, let colon = trimmed.lastIndex(of: ":"),
              let port = Int(trimmed[trimmed.index(after: colon)...]) else {
            return (trimmed, defaultPort)
        }
        guard isValidPort(port) else {
            throw LampControlError.configuration(NSLocalizedString("error.yeelight.port.invalid", comment: ""))
        }
        let host = String(trimmed[..<colon])
        return host.isEmpty ? (trimmed, defaultPort) : (host, port)
    }
}
