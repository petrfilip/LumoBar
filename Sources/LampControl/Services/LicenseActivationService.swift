import Foundation

struct LicenseProviderConfig {
    static let providerName = "Lemon Squeezy"
    static let checkoutURL = "https://lemonsqueezy.com/checkout"
    static let apiBase = "https://api.lemonsqueezy.com/v1"
    static let expectedStoreID = "YOUR_STORE_ID_HERE"
    static let expectedProductID = "YOUR_PRODUCT_ID_HERE"
    static let expectedVariantID = "YOUR_VARIANT_ID_HERE"
}

enum LicenseActivationError: LocalizedError {
    case invalidLicenseKey
    case invalidEmail
    case networkError
    case apiError(String)
    case decodingError
    case alreadyActivated
    case licenseExpired

    var errorDescription: String? {
        switch self {
        case .invalidLicenseKey:
            return "Invalid license key"
        case .invalidEmail:
            return "Invalid email address"
        case .networkError:
            return "Network error"
        case .apiError(let message):
            return message
        case .decodingError:
            return "Could not decode license data"
        case .alreadyActivated:
            return "License already activated"
        case .licenseExpired:
            return "License has expired"
        }
    }
}

final class LicenseActivationService {
    func activate(licenseKey: String, expectedEmail: String?) async throws -> LicenseState {
        guard !licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LicenseActivationError.invalidLicenseKey
        }

        let activationPayload: [String: Any] = [
            "license_key": licenseKey.trimmingCharacters(in: .whitespacesAndNewlines),
            "instance_name": Host.current().localizedName ?? "Unknown",
            "app_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "1.0.0"
        ]

        let requestURL = URL(string: "\(LicenseProviderConfig.apiBase)/licenses/activate")!
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: activationPayload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LicenseActivationError.networkError
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 422 {
                throw LicenseActivationError.alreadyActivated
            }
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LicenseActivationError.apiError(errorMessage)
        }

        guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let licenseData = jsonResponse["license"] as? [String: Any] else {
            throw LicenseActivationError.decodingError
        }

        return try makeLicenseState(from: licenseData)
    }

    func validate(_ state: LicenseState) async throws -> LicenseState {
        guard let licenseKey = state.licenseKey, !licenseKey.isEmpty else {
            return state
        }

        let validationPayload: [String: Any] = [
            "license_key": licenseKey,
            "instance_id": state.instanceID ?? UUID().uuidString
        ]

        let requestURL = URL(string: "\(LicenseProviderConfig.apiBase)/licenses/validate")!
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: validationPayload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LicenseActivationError.networkError
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            // 5xx / 429 / 408 say nothing about the license; other 4xx do.
            if LicenseValidationPolicy.isTransientHTTPStatus(httpResponse.statusCode) {
                throw LicenseActivationError.networkError
            }
            throw LicenseActivationError.apiError(String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)")
        }

        guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let licenseData = jsonResponse["license"] as? [String: Any] else {
            throw LicenseActivationError.decodingError
        }

        return try makeLicenseState(from: licenseData, previousState: state)
    }

    func deactivate(_ state: LicenseState) async throws {
        guard let licenseKey = state.licenseKey, let instanceID = state.instanceID else {
            return
        }

        let deactivationPayload: [String: Any] = [
            "license_key": licenseKey,
            "instance_id": instanceID
        ]

        let requestURL = URL(string: "\(LicenseProviderConfig.apiBase)/licenses/deactivate")!
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: deactivationPayload)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LicenseActivationError.networkError
        }
    }

    private func makeLicenseState(from licenseData: [String: Any], previousState: LicenseState? = nil) throws -> LicenseState {
        let isValid = licenseData["valid"] as? Bool ?? false
        let tier: LicenseTier = isValid ? .premium : .free

        let licenseKey = licenseData["license_key"] as? String ?? previousState?.licenseKey
        let instanceID = licenseData["instance_id"] as? String ?? UUID().uuidString
        let customerEmail = licenseData["customer_email"] as? String ?? previousState?.customerEmail
        let instanceName = licenseData["instance_name"] as? String ?? previousState?.instanceName
        let productName = (licenseData["product"] as? [String: Any])?["name"] as? String ?? previousState?.productName

        return LicenseState(
            tier: tier,
            provider: .lemonSqueezy,
            licenseKey: licenseKey,
            instanceID: instanceID,
            instanceName: instanceName,
            customerEmail: customerEmail,
            productName: productName,
            activatedAt: previousState?.activatedAt ?? Date(),
            validatedAt: Date()
        )
    }
}

