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
            return String(format: NSLocalizedString("error.tuya.http", comment: ""), status)
        case .invalidResponse:
            // Shared by every provider (Yeelight, Hue, LIFX, …), not only Tuya.
            return NSLocalizedString("error.invalid.response", comment: "")
        case .offline:
            return NSLocalizedString("error.offline", comment: "")
        }
    }
}
