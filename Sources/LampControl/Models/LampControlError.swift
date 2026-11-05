import Foundation

enum LampControlError: LocalizedError {
    case configuration(String)
    case keychain(String)
    case tuya(String)
    case http(Int)
    case invalidResponse
    case offline

    var errorDescription: String? {
        switch self {
        case .configuration(let message), .keychain(let message), .tuya(let message):
            return message
        case .http(let status):
            return "Tuya HTTP \(status). Vérifiez la région, les identifiants et les services Cloud activés."
        case .invalidResponse:
            // Shared by every provider (Yeelight, Hue, LIFX, …), not only Tuya.
            return NSLocalizedString("error.invalid.response", comment: "")
        case .offline:
            return "Appareil hors ligne."
        }
    }
}
