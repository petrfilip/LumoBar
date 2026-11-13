import Foundation

final class NanoleafClient {
    private let session: URLSession

    init(session: URLSession = ServiceSession.lan) {
        self.session = session
    }

    func pairDevice(host: String, port: Int = 16021) async throws -> String {
        guard let url = URL(string: "http://\(host):\(port)/api/v1/new") else {
            throw LampControlError.configuration(NSLocalizedString("error.nanoleaf.address.invalid", comment: ""))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LampControlError.invalidResponse
        }

        if httpResponse.statusCode == 403 {
            throw LampControlError.configuration(NSLocalizedString("error.nanoleaf.pairing", comment: ""))
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LampControlError.http(httpResponse.statusCode)
        }

        let auth = try JSONDecoder().decode(NanoleafAuthResponse.self, from: data)
        return auth.auth_token
    }

    func fetchState(device: NanoleafDevice) async throws -> NanoleafStateResponse {
        guard let url = URL(string: "\(device.baseURL)/\(device.authToken)") else {
            throw LampControlError.configuration(NSLocalizedString("error.nanoleaf.url.invalid", comment: ""))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LampControlError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LampControlError.http(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(NanoleafStateResponse.self, from: data)
    }

    func setPower(device: NanoleafDevice, value: Bool) async throws {
        try await putState(device: device, body: NanoleafPowerBody(value))
    }

    func setBrightness(device: NanoleafDevice, value: Int) async throws {
        try await putState(device: device, body: NanoleafBrightnessBody(value))
    }

    func setCT(device: NanoleafDevice, value: Int) async throws {
        try await putState(device: device, body: NanoleafCTBody(value))
    }

    func setHS(device: NanoleafDevice, hue: Int, sat: Int) async throws {
        try await putState(device: device, body: NanoleafHSBody(hue: hue, sat: sat))
    }

    private func putState<Body: Encodable>(device: NanoleafDevice, body: Body) async throws {
        guard let url = URL(string: "\(device.baseURL)/\(device.authToken)/state") else {
            throw LampControlError.configuration(NSLocalizedString("error.nanoleaf.url.invalid", comment: ""))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LampControlError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LampControlError.http(httpResponse.statusCode)
        }
    }
}
