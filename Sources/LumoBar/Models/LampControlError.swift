import Foundation

enum LampControlError: LocalizedError {
    case configuration(String)
    case keychain(String)
    case tuya(String)
    /// Error reported by a Yeelight bulb or raised while talking to it (message is already localized).
    case yeelight(String)
    /// Generic provider/device error for non-Tuya, non-Yeelight providers (LIFX, Govee, Hue).
    case device(String)
    case http(Int)
    case invalidResponse
    case offline

    var errorDescription: String? {
        switch self {
        case .configuration(let message), .keychain(let message), .tuya(let message), .yeelight(let message), .device(let message):
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
