import Foundation

struct HueSettings: Codable, Equatable {
    var bridgeID = ""
    var bridgeIP = ""
    var username = ""

    var isConfigured: Bool {
        !bridgeIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    enum CodingKeys: String, CodingKey { case bridgeID, bridgeIP, username }
}

extension HueSettings {
    /// Explicit so a field missing from an old file falls back to its default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bridgeID = try c.decodeIfPresent(String.self, forKey: .bridgeID) ?? ""
        bridgeIP = try c.decodeIfPresent(String.self, forKey: .bridgeIP) ?? ""
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
    }
}

struct HueBridge: Identifiable, Codable, Equatable {
    let id: String
    let internalipaddress: String
    let port: Int?

    var displayAddress: String {
        if let port, port != 80 {
            return "\(internalipaddress):\(port)"
        }

        return internalipaddress
    }
}

struct HueLightDTO: Decodable {
    let name: String
    let state: HueLightStateDTO
}

struct HueLightStateDTO: Decodable {
    let on: Bool
    let bri: Int?
    let hue: Int?
    let sat: Int?
    let ct: Int?
    let reachable: Bool?
}

enum HueAPIItem: Decodable {
    case success([String: HueFlexibleValue])
    case error(HueAPIError)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let success = try container.decodeIfPresent([String: HueFlexibleValue].self, forKey: .success) {
            self = .success(success)
        } else {
            self = .error(try container.decode(HueAPIError.self, forKey: .error))
        }
    }

    private enum CodingKeys: String, CodingKey {
        case success
        case error
    }
}

struct HueAPIError: Decodable {
    let type: Int?
    let address: String?
    let description: String
}

enum HueFlexibleValue: Decodable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else {
            self = .null
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}
