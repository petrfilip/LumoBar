import Foundation

struct YeelightSettings: Codable, Equatable {
    var bulbs: [YeelightBulb] = []

    var isConfigured: Bool {
        !bulbs.isEmpty
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
