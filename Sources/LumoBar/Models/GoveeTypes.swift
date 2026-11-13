import Foundation

struct GoveeSettings: Codable, Equatable {
    var apiKey = ""

    var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct GoveeDevicesResponse: Decodable {
    let data: GoveeDevicesPayload
}

struct GoveeDevicesPayload: Decodable {
    let devices: [GoveeDeviceDTO]
}

struct GoveeDeviceDTO: Decodable {
    let device: String
    let model: String
    let deviceName: String
    let controllable: Bool
    let retrievable: Bool
    let supportCmds: [String]
    let properties: GoveeDevicePropertiesDTO?
}

struct GoveeDevicePropertiesDTO: Decodable {
    let colorTem: GoveeRangeDTO?
}

struct GoveeRangeDTO: Decodable {
    let range: GoveeRangeBoundsDTO?
}

struct GoveeRangeBoundsDTO: Decodable {
    let min: Int
    let max: Int
}

struct GoveeStateResponse: Decodable {
    let data: GoveeStatePayload
}

struct GoveeStatePayload: Decodable {
    let device: String
    let model: String
    let properties: [GoveeStatePropertyDTO]
}

struct GoveeStatePropertyDTO: Decodable {
    let online: Bool?
    let powerState: String?
    let brightness: Int?
    let color: GoveeColorDTO?
    let colorTem: Int?

    private enum CodingKeys: String, CodingKey {
        case online
        case powerState
        case brightness
        case color
        case colorTem
    }
}

struct GoveeColorDTO: Decodable {
    let r: Int
    let g: Int
    let b: Int
}

struct GoveeControlBody: Encodable {
    let device: String
    let model: String
    let cmd: GoveeCommand
}

struct GoveeCommand: Encodable {
    let name: String
    let value: GoveeCommandValue
}

enum GoveeCommandValue: Encodable {
    case string(String)
    case int(Int)
    case color(r: Int, g: Int, b: Int)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .color(let r, let g, let b):
            try container.encode(["r": r, "g": g, "b": b])
        }
    }
}
