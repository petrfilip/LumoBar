import Foundation

enum TuyaRegion: String, Codable, CaseIterable, Hashable {
    case eu
    case us
    case usEast
    case cn
    case `in`
    case custom
}

extension TuyaRegion {
    /// A region written by a newer version decodes as `.custom`: the stored endpoint is kept, so
    /// the account still works and the file is not rejected as a whole.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TuyaRegion(rawValue: raw) ?? .custom
    }
}

struct TuyaSettings: Codable, Equatable {
    var accessId = ""
    var accessSecret = ""
    var endpoint = TuyaRegion.eu.defaultEndpoint
    var uid = ""
    var region: TuyaRegion = .eu

    mutating func applyEndpoint(for region: TuyaRegion) {
        guard region != .custom else { return }
        endpoint = region.defaultEndpoint
    }
}

extension TuyaRegion {
    var defaultEndpoint: String {
        switch self {
        case .eu:
            return "https://openapi.tuyaeu.com"
        case .us:
            return "https://openapi.tuyaus.com"
        case .usEast:
            return "https://openapi-ueaz.tuyaus.com"
        case .cn:
            return "https://openapi.tuyacn.com"
        case .in:
            return "https://openapi.tuyain.com"
        case .custom:
            return ""
        }
    }
}

struct StoredSettings: Codable {
    var accessId: String
    var endpoint: String
    var uid: String
    var region: TuyaRegion

    enum CodingKeys: String, CodingKey { case accessId, endpoint, uid, region }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessId = try c.decodeIfPresent(String.self, forKey: .accessId) ?? ""
        endpoint = try c.decodeIfPresent(String.self, forKey: .endpoint) ?? TuyaRegion.eu.defaultEndpoint
        uid = try c.decodeIfPresent(String.self, forKey: .uid) ?? ""
        region = try c.decodeIfPresent(TuyaRegion.self, forKey: .region) ?? .eu
    }

    init(settings: TuyaSettings) {
        accessId = settings.accessId.trimmingCharacters(in: .whitespacesAndNewlines)
        endpoint = settings.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        uid = settings.uid.trimmingCharacters(in: .whitespacesAndNewlines)
        region = settings.region
    }

    func toSettings() -> TuyaSettings {
        TuyaSettings(accessId: accessId, accessSecret: "", endpoint: endpoint, uid: uid, region: region)
    }
}

struct SettingsSnapshot {
    var settings: TuyaSettings
    var hasSecret: Bool
}
