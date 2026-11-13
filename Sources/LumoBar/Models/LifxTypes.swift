import Foundation

struct LifxSettings: Codable, Equatable {
    var token = ""

    var isConfigured: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct LifxLightDTO: Decodable {
    let id: String
    let label: String
    let connected: Bool
    let power: String
    let color: LifxColorDTO?
    let brightness: Double?
    let product: LifxProductDTO?
}

struct LifxColorDTO: Decodable {
    let hue: Double?
    let saturation: Double?
    let kelvin: Int?
}

struct LifxProductDTO: Decodable {
    let capabilities: LifxCapabilitiesDTO?
}

struct LifxCapabilitiesDTO: Decodable {
    let hasColor: Bool?
    let hasVariableColorTemp: Bool?

    private enum CodingKeys: String, CodingKey {
        case hasColor = "has_color"
        case hasVariableColorTemp = "has_variable_color_temp"
    }
}

struct LifxStateCommand: Encodable {
    var power: String?
    var color: String?
    var brightness: Double?
    var duration: Double?
    var fast: Bool?
}
